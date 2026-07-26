# NeedHub

A community platform that connects people with needs to people who can help — built for InovaHack 2026.

---

## Admin Access

The admin panel is available at:

```
https://needhub-admin-production.up.railway.app
```

**Admin Secret Key:** `admin-dev-secret`

Enter this code on the admin login screen. From the dashboard you can:
- View and manage all posted needs
- Review and approve / reject certificates
- Handle user reports and flagged content
- See auto-blocked content from the profanity filter
- Manage registered users

---

## Live API

```
https://needhubapi-production.up.railway.app
```

Health check: `GET /health` → `{ "ok": true }`

---

## Mobile App — Device Requirements

For the best experience, install the APK on a device that meets these specs:

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| OS | Android 8.0 (API 26) | Android 11+ (API 30+) |
| RAM | 2 GB | 4 GB+ |
| Storage | 100 MB free | 500 MB free |
| Internet | Mobile data or WiFi | Stable WiFi or 4G / 5G |
| Camera | Any rear camera | Front + rear camera |

> The app requires an active internet connection to the live API. It will **not** work on restricted networks that block external domains (some college / office Wi-Fi).

### Installing the APK

1. Download the APK file to your Android device
2. Go to **Settings → Security → Install unknown apps** and allow installation from your file manager or browser
3. Open the APK and tap **Install**
4. Launch **NeedHub** from your home screen

> If the app crashes immediately on launch, you may have the wrong architecture build. Use the universal `app-release.apk` instead of the split-per-abi variants.

---

## Demo Credentials

These accounts are pre-loaded via the seed and ready to use:

| Email | Password |
|-------|----------|
| `aarav.kumar@needhub.demo` | `Demo1234!` |
| `meera.kulkarni@needhub.demo` | `Demo1234!` |
| `rohan.verma@needhub.demo` | `Demo1234!` |
| `priya.nair@needhub.demo` | `Demo1234!` |

> OTP verification is bypassed in demo mode — the app auto-fills the code after signup so you can skip straight to step 2 of onboarding.

---

## Re-seeding Demo Data

To wipe and re-populate all demo data (users, needs, chats, certificates, notifications, etc.) without shell access:

```bash
curl -X POST \
  -H "x-admin-secret: admin-dev-secret" \
  https://needhubapi-production.up.railway.app/admin/seed
```

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Mobile | Flutter (Dart) |
| Backend | Node.js + Express + TypeScript |
| Database | PostgreSQL via Prisma ORM |
| AI Decomposition | Grok (xAI) — `grok-3-mini` |
| Hosting | Railway |
| File Storage | Cloudflare R2 |

---

## Repo Layout

```
needhub/
├── apps/
│   ├── mobile/        # Flutter Android app
│   ├── api/           # Express + Prisma backend
│   └── admin/         # Next.js admin panel
└── packages/
    └── shared/        # Shared TypeScript types
```

---

## Team

Built for InovaHack 2026.
