// Edge Function: create-payment
//
// Создаёт счёт в CloudPayments и возвращает ссылку на оплату.
// Вызывается из приложения с токеном пользователя. Секрет CloudPayments
// живёт только здесь (в секретах Supabase), в приложение не попадает.
//
// Секреты (Supabase → Edge Functions → Secrets):
//   CLOUDPAYMENTS_PUBLIC_ID   — Public ID из личного кабинета CloudPayments
//   CLOUDPAYMENTS_API_SECRET  — API-пароль (секрет) оттуда же
// SUPABASE_URL и SUPABASE_SERVICE_ROLE_KEY подставляются автоматически.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const PRICES = {
  pro_client: 4900,
  pro_supplier: 9900, // заменить на вашу цену тарифа поставщика
  boost: { 1: 1500, 3: 3500, 7: 7000 } as Record<number, number>,
};

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  try {
    const publicId = Deno.env.get('CLOUDPAYMENTS_PUBLIC_ID')!;
    const apiSecret = Deno.env.get('CLOUDPAYMENTS_API_SECRET')!;
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    // Кто платит — по токену пользователя
    const authHeader = req.headers.get('Authorization') ?? '';
    const userClient = createClient(supabaseUrl, serviceKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json({ error: 'Нужно войти' }, 401);

    const body = await req.json();
    const kind: string = body.kind;
    const supplierId = body.supplier_id ? Number(body.supplier_id) : null;

    // Сроки и количество ограничиваем на сервере: из приложения нельзя
    // оформить «Pro на 999 месяцев» или сотни бустов одним счётом.
    const clamp = (v: unknown, min: number, max: number) => {
      const n = Math.floor(Number(v));
      return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : min;
    };
    const months = clamp(body.months ?? 1, 1, 12);
    const boostDays = Number(body.boost_days ?? 1); // допустимость проверим ниже по прайсу
    const boostQty = clamp(body.boost_qty ?? 1, 1, 20);

    // Сумма считается на сервере — из приложения цену не принимаем
    let amount = 0;
    let description = '';
    if (kind === 'pro_client') {
      amount = PRICES.pro_client * months;
      description = `КОМПЛЕКТ Про, ${months} мес.`;
    } else if (kind === 'pro_supplier') {
      amount = PRICES.pro_supplier * months;
      description = `Тариф Про поставщика, ${months} мес.`;
    } else if (kind === 'boost') {
      const per = PRICES.boost[boostDays];
      if (!per) return json({ error: 'Неверный срок буста' }, 400);
      amount = per * boostQty;
      description = `Буст: ${boostQty} × ${boostDays} дн.`;
    } else {
      return json({ error: 'Неизвестный тип оплаты' }, 400);
    }

    const admin = createClient(supabaseUrl, serviceKey);

    // Тариф поставщика и буст — только для СВОЕЙ компании. Если передан
    // чужой supplier_id, отклоняем; если не передан — берём компанию юзера.
    let effectiveSupplierId: number | null = null;
    if (kind === 'pro_supplier' || kind === 'boost') {
      const { data: mine } = await admin
        .from('suppliers')
        .select('id')
        .eq('owner_id', user.id)
        .order('id')
        .limit(1)
        .maybeSingle();
      if (!mine) {
        return json({ error: 'У вас нет компании поставщика' }, 400);
      }
      if (supplierId !== null && supplierId !== mine.id) {
        return json({ error: 'Можно оплачивать только свою компанию' }, 403);
      }
      effectiveSupplierId = mine.id;
    }

    // Запись платежа
    const { data: pay, error: payErr } = await admin
      .from('payments')
      .insert({
        user_id: user.id,
        kind,
        amount,
        months: kind === 'boost' ? null : months,
        boost_days: kind === 'boost' ? boostDays : null,
        boost_qty: kind === 'boost' ? boostQty : null,
        supplier_id: effectiveSupplierId,
      })
      .select('id')
      .single();
    if (payErr) throw payErr;

    // Счёт в CloudPayments (Orders API). В JsonData кладём id платежа —
    // он вернётся в вебхуке, по нему и выдаём.
    const auth = 'Basic ' + btoa(`${publicId}:${apiSecret}`);
    const cpRes = await fetch('https://api.cloudpayments.ru/orders/create', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: auth },
      body: JSON.stringify({
        Amount: amount,
        Currency: 'KZT',
        Description: description,
        Email: user.email,
        JsonData: { paymentId: pay.id },
      }),
    });
    const cp = await cpRes.json();
    if (!cp.Success) {
      return json({ error: cp.Message ?? 'CloudPayments отклонил счёт' }, 400);
    }

    await admin.from('payments')
      .update({ invoice_id: String(cp.Model.Id) })
      .eq('id', pay.id);

    return json({ url: cp.Model.Url, paymentId: pay.id });
  } catch (e) {
    return json({ error: String(e?.message ?? e) }, 500);
  }
});

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}
