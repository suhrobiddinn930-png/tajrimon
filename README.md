# tajrimon

Flutter + Supabase + FastAPI asosidagi ikki kishilik ovozli tarjimonning texnik poydevori va
qisqa nutq navbatlari bilan ishlaydigan MVP kodi. **Production yoki investor namoyishiga tayyor deb
tasdiqlanmagan:** haqiqiy AI kalitlari, Supabase loyihasi va ikki telefondagi yakuniy sinovlar kerak.

## Yaratilgan qismlar

- `supabase/migrations/`: olti asosiy jadval, FK/index/constraint, RLS, updated_at va Auth triggerlari,
  xonaga kirish/yopish RPC, ikki ishtirokchi cheklovi, atomik daqiqa rezervatsiyasi.
- `backend/`: Supabase token tekshiruvi, xona API, qisqa muddatli bir martalik WSS tokeni,
  mustaqil ikki yo‘nalishli audio relay, almashtiriladigan STT → tarjima → TTS adapteri,
  server limitlari, tarix, account deletion va xavfsiz xatolar.
- `mobile/lib/`: Riverpod, GoRouter, Material 3 light/dark, onboarding, email auth/reset,
  til juftligi, xona/QR, vaqtinchalik transkriptli audio ekran, qurilmalar, tarix, profil/maxfiylik,
  tarif va foydalanish ko‘rinishi. Ishlamaydigan to‘lov tugmasi yo‘q.
- `backend/tests/`: offline unit/API/WebSocket testlari va alohida haqiqiy PostgreSQL/RLS testlari.
- `scripts/bootstrap_mobile.py`: Flutter SDK orqali Android/iOS runnerlarini xavfsiz yaratish.

Arxitektura va MVP cheklovlari: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
Qurilma va release sinovlari: [docs/DEVICE_ACCEPTANCE.md](docs/DEVICE_ACCEPTANCE.md).
Mobil yig‘ish: [mobile/README.md](mobile/README.md).

## Hisoblar va kalitlar

1. [Supabase dashboard](https://supabase.com/dashboard) orqali alohida loyiha oching. Project URL,
   public anon key va server-only service role keyni loyiha API sozlamalaridan oling. Email tasdiqlashni
   yoqing, ishlab chiqarishda SMTP/CAPTCHA/Auth rate limitlarini sozlang.
2. [OpenAI API dashboard](https://platform.openai.com/api-keys) orqali server loyihasi uchun kalit oling;
   API billing va sarf limitini belgilang. ChatGPT obunasi API krediti o‘rnini bosmaydi.
3. Kalitlarni chatga yubormang. `.env.example` nusxasidan `.env` yarating va faqat lokal/server sirlar
   sozlamalarida to‘ldiring. Fayl Git tomonidan e’tiborga olinmaydi. `ROOM_CODE_PEPPER`ni mahalliy
   kriptografik generator bilan yarating; almashtirish mavjud taklif kodlarini bekor qiladi.

```powershell
Copy-Item .env.example .env
python -c "import secrets; print(secrets.token_hex(32))"
```

## Supabase bazasi

Docker Desktop va [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started)
o‘rnatilgan mahalliy muhitda:

```powershell
supabase start
supabase migration up --local
```

Mavjud hosted loyihada avval staging bazada sinang; keyin `supabase login`,
`supabase link --project-ref YOUR_PROJECT_REF`, `supabase db push` orqali migratsiyalarni qo‘llang.
Bu buyruqlar tashqi bazani o‘zgartiradi; ushbu ish davomida tashqi deploy bajarilmadi.
Dashboard Auth URL Configuration’da `ai.live.translator://auth-callback/`ni redirect allowlistga kiriting.
Supabase `.env` qiymatlari aynan shu bazaga tegishli bo‘lsin. Yangi loyiha foydalanuvchilari trigger
orqali profil, afzallik va Free entitlement oladi; eski foydalanuvchili bazaga alohida backfill kerak.

## Backendni ishga tushirish

Python 3.12 tavsiya etiladi; buyruqlar repository ildizidan bajariladi:

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -r backend/requirements-dev.txt
.venv\Scripts\python -m uvicorn backend.api.app:app --env-file .env --host 0.0.0.0 --port 8000 --workers 1 --ws-max-size 500000 --ws-max-queue 1 --no-access-log
```

`uvicorn[standard]` `.env` uchun python-dotenvni o‘rnatadi. `GET /health` jarayon holatini tekshiradi;
bu to‘liq upstream readiness testi emas. `/docs` endpoint sxemalarini ko‘rsatadi.
Bir worker va bir replica shart: sessiyalar, rate limit va audio presence xotirada.
HTTPS/WSS reverse proxy ishlating; HTTP body limit 16 KB, WS frame limit 500 KB, handshake/IP rate
limit, 90 soniyadan uzun proxy idle timeout va access/request-body loggingni o‘chirish kerak.

## Mobil ishga tushirish va ikki telefon sinovi

`python scripts/bootstrap_mobile.py` bajaring va [mobile/README.md](mobile/README.md)ni kuzating.
Ikki tasdiqlangan hisob bilan ikki telefonda kiring. A: English → Deutsch, B: Deutsch → English.
A xona ochadi, B kod/QR bilan kiradi. Ikkalasi quloqchin ulab, ovoz chiqishini tekshiradi va AI
processing roziligini belgilab audio sessiyasiga ulanadi. Mikrofonni bir marta bosish yozishni,
yana bosish tarjima yuborishni boshlaydi; 12 soniyada avtomatik to‘xtaydi. A gapi faqat Bga,
B gapi faqat Aga ovoz sifatida yuboriladi. Ikkalasida matn vaqtincha ko‘rinadi.

Ilova fonda yoki qurilma uzilganda audio to‘xtaydi. Qayta ulanish foydalanuvchi harakati bilan.
Suhbatdan chiqish ikkala tomon uchun xonani yopadi. Besh daqiqada audio sessiyasini qayta ulash
kerak; xona bir soat amal qiladi. Kod faqat bir marta ishlatiladi va qayta ko‘rsatilmaydi.

## Til va AI konfiguratsiyasi

Standart: `en,de,ru,tr`. O‘zbek tili sifat jihatidan hali tekshirilmagan, shuning uchun standartda
o‘chiq. Faqat nazoratli sinov uchun `ENABLED_LANGUAGES=uz,en,de,ru,tr` va
`EXPERIMENTAL_UZBEK=true` belgilang. Pipeline mavjudligi o‘zbek ASR/TTS sifati kafolati emas.
Qo‘llab-quvvatlanmagan tilni ishlayapti deb ko‘rsatmang; mos boshqa adapter bilan almashtirish mumkin.

OpenAI rasmiy hujjatlari 2026-10-23 kuni tekshirildi:
[STT](https://developers.openai.com/api/docs/guides/speech-to-text),
[TTS](https://developers.openai.com/api/docs/guides/text-to-speech),
[Responses](https://developers.openai.com/api/docs/guides/text).
Joriy fallback `gpt-4o-mini-transcribe`, `gpt-4.1-mini`, `gpt-4o-mini-tts`ni konfiguratsiyadan oladi.
Rasmiy sahifalarda STT modelining 2027-02-26, TTS modelining 2027-01-06 yopilishi ko‘rsatilgan.
Bu compatibility adapter: TTS yopilishidan oldin Realtime adapterga ko‘chirish zarur;
Realtime model nomini `/audio/speech`ga shunchaki almashtirish yetarli emas.
AI kalitlari va provayderning umumiy tokenlari mobilga berilmaydi; `/ai/session` bizning WSS
serverimiz uchun 60 soniyalik bir martalik token beradi. Bevosita Realtime/WebRTC adapter hali yo‘q.

## Limitlar, maxfiylik va obuna

Free 10, Pro 120, Business 600 daqiqa/UTC kalendar oy. Limitlar serverda tekshiriladi;
subscription qatorini faqat ishonchli server boshqaradi. Haqiqiy payment provider va store billing
ulanmagan; pullik tariflar pilot entitlement hisoblanadi. Hech qanday to‘lov muvaffaqiyati soxtalashtirilmaydi.
Har yuborilgan nutq navbati provayderdan oldin rezerv qilinadi, xato yoki yetkazilmagan holatda ham
sarflangan hisoblanadi. `ESTIMATED_USD_PER_MINUTE` operator bahosi; haqiqiy billing emas.

Audio/transkript bazaga yoki server logiga yozilmaydi. Mobil xotiradagi yozuv/playback bufferlari
va vaqtinchalik matn ekrandan chiqishda tozalanadi. Provayderga yuborilgan audio uchun retention
API hisobingiz data controls shartlariga bog‘liq; `store:false` Responses so‘roviga qo‘yiladi.
Transkriptni doimiy saqlash funksiyasi bu MVPda yo‘q. Account deletion autentifikatsiya bilan
serverda bajariladi va shaxsiy yozuvlar FK orqali o‘chiriladi.

## Testlar

Haqiqiy Supabase Auth/RLS va lokal API oqimini AI xarajatisiz tekshirish:
avval `python scripts/run_web.py --no-build`, keyin `python scripts/check_user_flow.py`.
Bu sinov email yubormasdan uchta vaqtinchalik tasdiqlangan hisob yaratadi, xona/limit/tarixni
tekshiradi va faqat o‘zi yaratgan hisoblarni oxirida o‘chiradi. Provider audio sinovi emas.
Android debug APK yig‘ish va USB orqali ishlatish: [mobile/README.md](mobile/README.md).

```powershell
python -m pytest -q
ruff check backend scripts
ruff format --check backend scripts
```

Haqiqiy RLS testi uchun **faqat alohida lokal Supabase** bazasida migratsiyalarni qo‘llang:

```powershell
$env:TEST_DATABASE_URL = 'postgresql://postgres:postgres@127.0.0.1:54322/postgres'
python -m pytest -q -m integration
```

RLS testlari haqiqiy PostgreSQL rollari bilan ishlaydi va fixturelarni rollback qiladi.
`TEST_DATABASE_URL` bo‘lmasa ular skip bo‘ladi; offline mock testlari RLS tekshiruvi o‘rnini bosmaydi.
Joriy muhit natijalari va bajarilmagan tekshiruvlar [docs/TEST_RESULTS.md](docs/TEST_RESULTS.md)da.

## Deploy

```powershell
docker build -f backend/Dockerfile -t ai-live-translator .
docker run --rm --env-file .env -p 8000:8000 ai-live-translator
```

Doimiy WebSocketni qo‘llaydigan container hostingga bir replica joylang; public HTTPS ingress va
server secret store sozlang. Odatdagi qisqa muddatli serverless endpoint audio socket uchun mos emas.
Supabase Auth/database/Realtime alohida control plane hisoblanadi; Supabase audio AI emas.
Android debug/release va iOS Xcode buyruqlari mobil qo‘llanmada. Store release va hosted deploy
bajarilmadi. Investor namoyishidan avval qurilma matritsasi, haqiqiy provider, RLS va limit
raqobat sinovlarini yakunlang. Bajarilmagan funksiyalar arxitektura hujjatida aniq ko‘rsatilgan.
