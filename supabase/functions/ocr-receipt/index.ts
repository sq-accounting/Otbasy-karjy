// Отбасы қаржысы — чек суретін Gemini арқылы тану (Supabase Edge Function)
//
// Қауіпсіздік: GEMINI_API_KEY тек серверде (Supabase secret) тұрады, ешқашан
// браузерге шықпайды. Қосымша суретті осы функцияға жібереді, функция Gemini-ге
// сұраныс жасап, тауарлар тізімін JSON етіп қайтарады.
//
// Орнату (бір рет):
//   1) Google AI Studio → API key алыңыз (тегін деңгей жеткілікті).
//   2) supabase secrets set GEMINI_API_KEY=ВАШ_КЛЮЧ
//   3) supabase functions deploy ocr-receipt
//
// verify_jwt әдепкі қосулы — тек жүйеге кірген қолданушы шақыра алады.

const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.0-flash"; // тегін деңгейге сай

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

const PROMPT =
  "Бұл — дүкен/супермаркет чегінің суреті. Тек САТЫЛҒАН ТАУАРЛАРДЫ JSON массив " +
  'етіп қайтар: [{"name":"тауар атауы","amount":сан}]. ' +
  "amount — сол позицияның жалпы бағасы (тек сан, теңге, бөлгішсіз). " +
  "Жалпы сома, 'итого/всего/барлығы', чек нөмірі, дата, уақыт, кассир, QR, " +
  "салық, сдача, төлем түрі сияқты жолдарды ҚОСПА. Тек таза JSON қайтар.";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  try {
    if (!GEMINI_KEY) return json({ error: "GEMINI_API_KEY not configured" }, 500);

    const { image, mime } = await req.json().catch(() => ({}));
    if (!image || typeof image !== "string") {
      return json({ error: "no image" }, 400);
    }
    // ~7MB base64 шегі (артық суретті қабылдамаймыз)
    if (image.length > 7_000_000) return json({ error: "image too large" }, 413);

    const payload = {
      contents: [{
        parts: [
          { text: PROMPT },
          { inline_data: { mime_type: mime || "image/jpeg", data: image } },
        ],
      }],
      generationConfig: { temperature: 0, responseMimeType: "application/json" },
    };

    const resp = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${GEMINI_KEY}`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(payload),
      },
    );

    const data = await resp.json().catch(() => ({}));
    if (!resp.ok) {
      const msg = data?.error?.message || `gemini ${resp.status}`;
      return json({ error: msg }, 502);
    }

    const text: string =
      data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "[]";

    let items: unknown = [];
    try {
      items = JSON.parse(text);
    } catch {
      const a = text.indexOf("["), b = text.lastIndexOf("]");
      if (a >= 0 && b > a) {
        try { items = JSON.parse(text.slice(a, b + 1)); } catch { items = []; }
      }
    }

    const clean = (Array.isArray(items) ? items : [])
      .map((x: any) => ({
        name: String(x?.name ?? x?.title ?? "").trim(),
        amount: Number(
          String(x?.amount ?? x?.price ?? x?.sum ?? 0)
            .replace(/\s/g, "").replace(",", "."),
        ) || 0,
      }))
      .filter((x) => x.name && x.amount > 0)
      .slice(0, 200);

    return json({ items: clean });
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
