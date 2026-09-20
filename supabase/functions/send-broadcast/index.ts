// ============================================================
// КОМПЛЕКТ · Edge Function "send-broadcast"
// Рассылка объявления всем, у кого установлено приложение.
// Вызывается из админки: supabase.functions.invoke('send-broadcast').
//
// Секреты те же, что у send-price-alerts (Dashboard → Edge Functions →
// Secrets): FCM_PROJECT_ID, FCM_CLIENT_EMAIL, FCM_PRIVATE_KEY.
// SUPABASE_URL, SUPABASE_ANON_KEY и SUPABASE_SERVICE_ROLE_KEY
// подставляются автоматически.
//
// ПРАВА ПРОВЕРЯЕМ ЗДЕСЬ, а не полагаемся на то, что кнопка спрятана.
// Функция ходит в базу с service_role, то есть мимо всех политик RLS;
// если не проверить роль самим, отправить рассылку всем пользователям
// сможет любой, кто знает её адрес.
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const FCM_PROJECT_ID = Deno.env.get("FCM_PROJECT_ID")!;
const FCM_CLIENT_EMAIL = Deno.env.get("FCM_CLIENT_EMAIL")!;
// В секрете перевод строки часто хранится как \n — восстанавливаем
const FCM_PRIVATE_KEY = (Deno.env.get("FCM_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;

const admin = createClient(
  SUPABASE_URL,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// PEM (PKCS#8) → ArrayBuffer для importKey
function pemToPkcs8(pem: string): ArrayBuffer {
  const b64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const bin = atob(b64);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

// OAuth2 access token для FCM (service account → JWT → token)
async function getAccessToken(): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(FCM_PRIVATE_KEY),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const jwt = await create(
    { alg: "RS256", typ: "JWT" },
    {
      iss: FCM_CLIENT_EMAIL,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: getNumericDate(0),
      exp: getNumericDate(3600),
    },
    key,
  );
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const json = await res.json();
  if (!json.access_token) throw new Error("OAuth error: " + JSON.stringify(json));
  return json.access_token as string;
}

type SendResult = { ok: boolean; invalidToken: boolean };

async function sendToToken(
  accessToken: string,
  token: string,
  title: string,
  body: string,
): Promise<SendResult> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          // Помечаем источник: приложение по этому полю отличает
          // объявление от уведомления о цене и не пытается открыть товар.
          data: { kind: "broadcast" },
          android: { priority: "high" },
          apns: { payload: { aps: { sound: "default" } } },
        },
      }),
    },
  );
  if (res.ok) return { ok: true, invalidToken: false };

  // Токен «протух» (приложение удалено / переустановлено) — удалим его.
  const text = await res.text();
  const invalidToken = res.status === 404 ||
    /UNREGISTERED|registration-token-not-registered|INVALID_ARGUMENT/i.test(text);
  return { ok: false, invalidToken };
}

const SEGMENTS = new Set(["all", "suppliers", "clients"]);

Deno.serve(async (req) => {
  try {
    // ── Кто зовёт ──
    // Токен пользователя приходит в заголовке; supabase-js подставляет его
    // сам при functions.invoke(). Сверяем роль в базе, а не в токене:
    // роль меняется в profiles, и старый JWT о её отзыве не знает.
    const auth = req.headers.get("Authorization") ?? "";
    const jwt = auth.replace(/^Bearer\s+/i, "");
    if (!jwt) return Response.json({ error: "Нет авторизации" }, { status: 401 });

    const { data: userRes } = await admin.auth.getUser(jwt);
    const uid = userRes?.user?.id;
    if (!uid) return Response.json({ error: "Нет авторизации" }, { status: 401 });

    const { data: profile } = await admin
      .from("profiles")
      .select("role")
      .eq("id", uid)
      .maybeSingle();
    if (profile?.role !== "admin") {
      return Response.json({ error: "Только для администратора" }, { status: 403 });
    }

    // ── Что отправляем ──
    const payload = await req.json().catch(() => ({}));
    const title = String(payload?.title ?? "").trim();
    const body = String(payload?.body ?? "").trim();
    const segment = String(payload?.segment ?? "all");

    if (!title || !body) {
      return Response.json({ error: "Пустой заголовок или текст" }, { status: 400 });
    }
    if (!SEGMENTS.has(segment)) {
      return Response.json({ error: "Неизвестный сегмент" }, { status: 400 });
    }

    const { data: targets, error: targetsError } = await admin
      .rpc("broadcast_targets", { p_segment: segment });
    if (targetsError) throw targetsError;

    const tokens = (targets ?? []).map((r: { token: string }) => r.token);

    // ── Журнал заводим ДО отправки ──
    // Если функция упадёт на середине, строка всё равно останется — иначе
    // получится рассылка, которой по документам не было.
    const { data: logRow } = await admin
      .from("broadcasts")
      .insert({
        title,
        body,
        segment,
        recipients: tokens.length,
        status: "sending",
        created_by: uid,
      })
      .select("id")
      .single();
    const logId = logRow?.id as number | undefined;

    if (tokens.length === 0) {
      if (logId) {
        await admin.from("broadcasts")
          .update({ status: "done", delivered: 0, failed: 0 })
          .eq("id", logId);
      }
      return Response.json({ recipients: 0, delivered: 0, failed: 0 });
    }

    const accessToken = await getAccessToken();
    let delivered = 0;
    let failed = 0;
    const deadTokens: string[] = [];

    for (const token of tokens) {
      const r = await sendToToken(accessToken, token, title, body);
      if (r.ok) delivered++;
      else failed++;
      if (r.invalidToken) deadTokens.push(token);
    }

    // Чистим невалидные токены, чтобы база не засорялась и счётчик
    // аудитории показывал реальное число, а не когда-то установленные копии.
    if (deadTokens.length > 0) {
      await admin.from("device_tokens").delete().in("token", deadTokens);
    }

    if (logId) {
      await admin.from("broadcasts")
        .update({ status: "done", delivered, failed })
        .eq("id", logId);
    }

    return Response.json({ recipients: tokens.length, delivered, failed });
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 500 });
  }
});
