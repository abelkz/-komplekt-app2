// Edge Function: cloudpayments-webhook
//
// Принимает уведомление об оплате от CloudPayments (Pay-уведомление).
// Проверяет подпись (HMAC-SHA256 тела запроса на API-секрете) и, если всё
// верно, вызывает fulfill_payment — она включает тариф или начисляет бусты.
//
// Адрес этой функции нужно вписать в личном кабинете CloudPayments как
// «Pay» (уведомление об успешной оплате). Ответ {code:0} = принято.
//
// Секрет: CLOUDPAYMENTS_API_SECRET (тот же, что у create-payment).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

Deno.serve(async (req) => {
  try {
    const apiSecret = Deno.env.get('CLOUDPAYMENTS_API_SECRET')!;
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    // Тело приходит form-urlencoded; для подписи нужен именно сырой текст
    const raw = await req.text();

    // Подпись: Base64( HMAC-SHA256( raw, apiSecret ) ) в заголовке Content-HMAC
    const sig =
      req.headers.get('Content-HMAC') ??
      req.headers.get('X-Content-HMAC') ??
      '';
    const ok = await verify(raw, sig, apiSecret);
    if (!ok) return json({ code: 13 }); // 13 — подпись неверна, не выдаём

    const form = new URLSearchParams(raw);
    const status = form.get('Status'); // Completed / Authorized
    if (status && status !== 'Completed' && status !== 'Authorized') {
      return json({ code: 0 });
    }

    let paymentId: string | null = null;
    try {
      paymentId = JSON.parse(form.get('Data') ?? '{}').paymentId ?? null;
    } catch (_) { /* нет данных — ниже отработаем */ }
    if (!paymentId) return json({ code: 0 });

    const admin = createClient(supabaseUrl, serviceKey);

    // Сверяем оплату с нашим счётом: подпись подтверждает, что уведомление
    // от CloudPayments, а это — что заплатили ровно ту сумму и в той валюте,
    // на которую мы выставили счёт. Иначе не выдаём.
    const { data: pay } = await admin
      .from('payments')
      .select('amount, status')
      .eq('id', paymentId)
      .maybeSingle();
    if (!pay) return json({ code: 0 }); // нет такого счёта — просто подтверждаем приём

    const paidAmount = Math.round(Number(form.get('Amount') ?? '0'));
    const currency = form.get('Currency') ?? 'KZT';
    if (currency !== 'KZT' || paidAmount < Number(pay.amount)) {
      // Сумма/валюта не совпали — не начисляем, но приём подтверждаем,
      // чтобы CloudPayments не долбил повторами. Разбираемся вручную.
      return json({ code: 0 });
    }

    const { error } = await admin.rpc('fulfill_payment', { p_payment: paymentId });
    if (error) {
      // Вернём ненулевой код — CloudPayments повторит уведомление позже
      return json({ code: 13 });
    }
    return json({ code: 0 });
  } catch (_) {
    return json({ code: 13 });
  }
});

async function verify(body: string, signature: string, secret: string) {
  if (!signature) return false;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(body),
  );
  const b64 = btoa(String.fromCharCode(...new Uint8Array(mac)));
  return b64 === signature;
}

function json(obj: unknown) {
  return new Response(JSON.stringify(obj), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}
