// ============================================================
// КОМПЛЕКТ · Edge Function "send-price-alerts"
// Рассылает пуш-уведомления о снижении цены через FCM HTTP v1.
// Вызывается Database Webhook при INSERT в public.price_drops.
//
// Секреты функции (Dashboard → Edge Functions → Secrets):
//   FCM_PROJECT_ID, FCM_CLIENT_EMAIL, FCM_PRIVATE_KEY
//   (берутся из service account JSON в Firebase → Project settings →
//    Service accounts → Generate new private key)
// SUPABASE_URL и SUPABASE_SERVICE_ROLE_KEY подставляются автоматически.
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const FCM_PROJECT_ID = Deno.env.get("FCM_PROJECT_ID")!;
const FCM_CLIENT_EMAIL = Deno.env.get("FCM_CLIENT_EMAIL")!;
// В секрете перевод строки часто хранится как \n — восстанавливаем
const FCM_PRIVATE_KEY = (Deno.env.get("FCM_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
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
  data: Record<string, string>,
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
          data,
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

function fmt(n: unknown): string {
  return Number(n ?? 0).toLocaleString("ru-RU");
}

Deno.serve(async (req) => {
  try {
    const payload = await req.json().catch(() => ({}));

    // Источник строк: одна запись из вебхука либо все pending (при ручном вызове)
    let rows: Array<Record<string, unknown>> = [];
    if (payload?.record) {
      rows = [payload.record];
    } else {
      const { data } = await supabase
        .from("price_drops")
        .select("*")
        .eq("status", "pending")
        .limit(100);
      rows = data ?? [];
    }

    if (rows.length === 0) {
      return Response.json({ sent: 0 });
    }

    const accessToken = await getAccessToken();
    let sent = 0;

    for (const row of rows) {
      const { data: tokens } = await supabase
        .from("device_tokens")
        .select("token")
        .eq("user_id", row.user_id as string);

      const title = "Цена снизилась 📉";
      const body =
        `${row.product_name}: ${fmt(row.new_price)} ₸ (было ${fmt(row.old_price)} ₸)`;

      let anyOk = false;
      const deadTokens: string[] = [];
      for (const t of tokens ?? []) {
        const r = await sendToToken(accessToken, t.token, title, body, {
          product_id: String(row.product_id ?? ""),
        });
        if (r.ok) anyOk = true;
        if (r.invalidToken) deadTokens.push(t.token);
      }
      // Чистим невалидные токены, чтобы не слать в пустоту
      if (deadTokens.length > 0) {
        await supabase.from("device_tokens").delete().in("token", deadTokens);
      }

      await supabase
        .from("price_drops")
        .update({
          status: anyOk ? "sent" : "error",
          sent_at: new Date().toISOString(),
        })
        .eq("id", row.id as number);

      if (anyOk) sent++;
    }

    return Response.json({ sent });
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 500 });
  }
});
