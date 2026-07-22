// ============================================================================
// photo-search — распознавание материалов на фото интерьера.
//
// Приложение шлёт сюда фотографию, функция показывает её Claude вместе со
// списком категорий из вашей базы и получает обратно строгий JSON: какие
// материалы видно и каким запросом их искать в каталоге.
//
// Ключ Anthropic живёт ТОЛЬКО здесь, в секретах Supabase. В приложение он
// не попадает — иначе его вытащат из веб-сборки за минуту.
//
// Развернуть:
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   supabase functions deploy photo-search
// ============================================================================

import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = "claude-opus-4-8";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Только POST" }, 405);

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    return json({ error: "На сервере не задан ANTHROPIC_API_KEY" }, 500);
  }

  let image: string, mediaType: string;
  try {
    const body = await req.json();
    image = body.image;
    mediaType = body.media_type ?? "image/jpeg";
    if (typeof image !== "string" || image.length < 100) {
      return json({ error: "Не пришло изображение" }, 400);
    }
  } catch {
    return json({ error: "Неверный формат запроса" }, 400);
  }

  // ── Категории и марки из живой базы: без них модель придумает свои ──
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
  );

  const [{ data: categories }, { data: brands }] = await Promise.all([
    supabase.from("categories").select("slug,name").order("sort"),
    supabase.from("brands").select("name").limit(50),
  ]);

  const cats = categories ?? [];
  if (cats.length === 0) return json({ error: "Каталог пуст" }, 500);

  const slugs = [...cats.map((c: { slug: string }) => c.slug), "other"];
  const catList = cats
    .map((c: { slug: string; name: string }) => `${c.slug} — ${c.name}`)
    .join("\n");
  const brandList = (brands ?? [])
    .map((b: { name: string }) => b.name)
    .join(", ");

  // Строгая схема ответа: модель физически не сможет вернуть другой формат
  const schema = {
    type: "object",
    properties: {
      room: { type: "string", description: "Что за помещение на фото" },
      style: { type: "string", description: "Стиль интерьера в двух словах" },
      materials: {
        type: "array",
        description: "Материалы, которые видно на фото — не больше шести",
        items: {
          type: "object",
          properties: {
            title: { type: "string", description: "Название материала для человека" },
            category_slug: {
              type: "string",
              enum: slugs,
              description: "Категория каталога; other — если ни одна не подходит",
            },
            query: {
              type: "string",
              description: "Поисковый запрос по каталогу: 2-4 слова, без кавычек и запятых",
            },
            color_hex: { type: "string", description: "Цвет материала как #rrggbb" },
            where: { type: "string", description: "Где на фото применён: пол, стена, фартук" },
          },
          required: ["title", "category_slug", "query", "color_hex", "where"],
          additionalProperties: false,
        },
      },
    },
    required: ["room", "style", "materials"],
    additionalProperties: false,
  };

  const prompt = `Ты подбираешь отделочные материалы по фотографии интерьера для строительного каталога в Казахстане.

Категории каталога:
${catList}

Марки, которые есть в каталоге: ${brandList || "—"}

Посмотри на фото и перечисли отделочные материалы, которые на нём видно: напольные покрытия, настенные, плитка, краска, двери, сантехника, свет. Не выдумывай того, чего не видно, и не описывай мебель и декор — только то, что покупают в строительном магазине.

Для каждого материала дай поисковый запрос из 2-4 слов на русском языке — так, как его назвал бы прораб в магазине: «керамогранит под бетон», «ламинат дуб светлый», «краска белая матовая». Не пиши марки, если не уверен.`;

  const client = new Anthropic({ apiKey });

  try {
    const response = await client.messages.create({
      model: MODEL,
      max_tokens: 2000,
      thinking: { type: "adaptive" },
      output_config: {
        effort: "low", // распознавание простое, а человек ждёт ответа
        format: { type: "json_schema", schema },
      },
      messages: [
        {
          role: "user",
          content: [
            {
              type: "image",
              source: { type: "base64", media_type: mediaType, data: image },
            },
            { type: "text", text: prompt },
          ],
        },
      ],
    });

    if (response.stop_reason === "refusal") {
      return json({ error: "Не удалось разобрать это изображение" }, 422);
    }

    const text = response.content.find((b) => b.type === "text");
    if (!text || text.type !== "text") {
      return json({ error: "Пустой ответ модели" }, 502);
    }

    const parsed = JSON.parse(text.text);
    return json({
      ...parsed,
      usage: {
        input_tokens: response.usage.input_tokens,
        output_tokens: response.usage.output_tokens,
      },
    });
  } catch (e) {
    console.error("photo-search:", e);
    const message = e instanceof Error ? e.message : String(e);
    if (message.includes("rate_limit")) {
      return json({ error: "Сервис перегружен, попробуйте через минуту" }, 429);
    }
    return json({ error: "Не удалось распознать фото" }, 502);
  }
});
