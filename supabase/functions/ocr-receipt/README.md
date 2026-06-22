# 📷 Чек суретін тану (ocr-receipt)

Бұл Supabase Edge Function чек суретін **Google Gemini** арқылы танып, тауарлар
тізімін қайтарады. Gemini API кілті **тек серверде** (Supabase secret) тұрады —
ашық сайт кодына ешқашан шықпайды.

## Орнату (бір рет)

### 1. Gemini API кілтін алу
1. https://aistudio.google.com/app/apikey ашыңыз (Google AI Studio).
2. **Create API key** → кілтті көшіріңіз.
3. Тегін деңгей отбасылық қолданысқа жеткілікті (billing қоспаңыз).

### 2. Supabase CLI орнату (бұрын орнатпаған болсаңыз)
```bash
npm install -g supabase
supabase login
```

### 3. Жобаға байлау
```bash
# project ref — Supabase Dashboard → Project Settings → General → Reference ID
supabase link --project-ref oujqwwaekajnyvyfohtm
```

### 4. Кілтті құпия (secret) ретінде сақтау  ⚠️ кілтті ешкімге жібермеңіз
```bash
supabase secrets set GEMINI_API_KEY=СІЗДІҢ_КІЛТІҢІЗ
# (қаласаңыз модельді ауыстыру)
# supabase secrets set GEMINI_MODEL=gemini-2.0-flash
```

### 5. Функцияны деплой жасау
```bash
supabase functions deploy ocr-receipt
```

Болды! Енді қосымшада **«Чек толтыру → 📷 Чектің суретін түсіру»** арқылы
сурет таңдасаңыз, тауарлар автоматты толады.

## Тексеру / ақаулар
- **"GEMINI_API_KEY not configured"** — 4-қадам жасалмаған.
- **401 / "Invalid JWT"** — қолданушы жүйеге кірмеген (функция тек кірген
  қолданушыға істейді).
- **"gemini 429"** — тегін деңгей лимиті (минут/күн) асып кетті, біраздан соң қайталаңыз.
- Логтар: `supabase functions logs ocr-receipt`.

## Қалай жұмыс істейді
1. Қосымша суретті браузерде 1280px-ке кішірейтіп, base64 етіп жібереді.
2. Функция қолданушының JWT-ін тексеріп (verify_jwt әдепкі қосулы), Gemini-ге
   сұраныс жасайды.
3. Gemini тек тауар + баға тізімін JSON етіп қайтарады, функция тазалап,
   `{ items: [{name, amount}] }` түрінде береді.
