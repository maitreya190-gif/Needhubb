# NeedHub Deployment Guide

Hackathon submission needs a live URL. Fastest path:

1. Deploy **API to Railway** (backend)
2. Build **Flutter APK** pointing at the Railway URL
3. Submit **API URL + APK download link**

---

## 1 · Deploy the API to Railway

### 1.1 Create the Railway project

- Go to [railway.app](https://railway.app) → **New Project** → **Deploy from GitHub repo**
- Select `maitreya190-gif/Needhubb`
- Set the **Root Directory** in Railway settings to `apps/api`

Railway will detect `railway.json` and use Nixpacks.

### 1.2 Set environment variables in Railway

Go to your service → **Variables** → paste each of these. **Do not put quotes around values** in Railway's UI.

**Required — Railway will crash without these:**

```
NODE_ENV=production
PORT=3000
AUTH_SECRET=REDACTED
ADMIN_SECRET=REDACTED
CORS_ORIGIN=*
API_BASE_URL=https://<your-railway-url>.up.railway.app
```

(Update `API_BASE_URL` to your actual Railway domain after first deploy — see 1.4.)

**Database (Neon):**

```
DATABASE_URL=postgresql://neondb_owner:REDACTED@ep-silent-flower-azz6wbyg-pooler.c-3.ap-southeast-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require
DIRECT_URL=postgresql://neondb_owner:REDACTED@ep-silent-flower-azz6wbyg.c-3.ap-southeast-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require
```

**Third-party APIs (copy from `apps/api/.env`):**

```
LLM_API_KEY=<from .env>
LLM_BASE_URL=https://api.groq.com/openai/v1
LLM_MODEL=llama-3.3-70b-versatile
COHERE_API_KEY=<from .env>
COHERE_MODEL=embed-english-light-v3.0
CLOUDINARY_CLOUD_NAME=<from .env>
CLOUDINARY_UPLOAD_PRESET=<from .env>
GMAIL_USER=<from .env>
GMAIL_APP_PASSWORD=<from .env>
RESEND_API_KEY=<from .env>
EMAIL_FROM=NeedHub <maitreya190@gmail.com>
LYZR_API_KEY=<from .env>
LYZR_AGENT_ID=<from .env>
LYZR_PERSONALITY_AGENT_ID=<from .env>
FACEPP_API_KEY=<from .env>
FACEPP_API_SECRET=<from .env>
CLERK_SECRET_KEY=<from .env>
CLERK_PUBLISHABLE_KEY=<from .env>
```

### 1.3 Trigger the deploy

Push to `main` — Railway auto-deploys on every push. First deploy takes ~3–5 min.

### 1.4 Grab your public URL

Railway → your service → **Settings** → **Networking** → click **Generate Domain**. You'll get something like `needhub-api-production.up.railway.app`. Copy it.

Now update the `API_BASE_URL` variable in Railway to that full `https://` URL and let it redeploy.

### 1.5 Smoke-test

```bash
curl https://<your-railway-url>.up.railway.app/health
# should return: {"ok":true}
```

If you get 502 or timeout, check Railway logs — most likely a missing env var.

---

## 2 · Build the Flutter APK with the Railway URL

On your machine:

```bash
cd apps/mobile
flutter build apk --release \
  --dart-define=API_URL=https://<your-railway-url>.up.railway.app
```

Output: `apps/mobile/build/app/outputs/flutter-apk/app-release.apk` (~40 MB)

Upload to **Google Drive** → right-click → **Get link** → set to "Anyone with the link".

---

## 3 · Submit

Give the hackathon organizers:

- **Live API:** `https://<your-railway-url>.up.railway.app`  (they can hit `/health`)
- **Android APK:** Google Drive link from step 2
- **Repo:** `https://github.com/maitreya190-gif/Needhubb`
- **Demo credentials (optional):** create a demo account by signing up in the APK, verify with OTP `000000` (dev bypass), share the email + password

---

## Post-submission hardening (do these before any real launch)

- [ ] Rotate every API key currently in `apps/api/.env` — they're all in git history and shouldn't stay in production
- [ ] Move `.env` to git-ignored and use Railway's env UI only
- [ ] Restrict `CORS_ORIGIN` from `*` to your actual client origins
- [ ] Add uptime monitoring on Railway (BetterStack / UptimeRobot free tier)
- [ ] Add a GitHub Actions CI to run `tsc --noEmit` + `flutter analyze` on every PR
- [ ] Configure `STORAGE_*` env vars if you want R2 uploads instead of Cloudinary

---

## Rollback

Railway keeps every deploy. **Settings** → **Deployments** → click a previous green deploy → **Redeploy**. Takes 30s.
