# Google Calendar API Integration — Implementation Plan

> Status: ACTIVE PLAN (Calendar first; Drive deferred)
> Model: Server-side OAuth (existing architecture) — NOT the native client-side model
> Last updated: 2026-06-14

---

## 1. Decision: Keep the Server-Side Model

The generic integration guide describes a **native client-side** flow
(`google_sign_in` + `googleapis` running on the device, tokens stored on-device).
This project already implements the **server-side** flow end-to-end, and Calendar
already reaches Google's consent screen.

We keep the server-side model because:

- It already works (reached consent; refresh-token + background sync logic complete).
- `TASK_DOCUMENT.md` requires clients to talk only to the backend and hold no
  provider secrets.
- Switching to native would discard working code (token refresh, busy-sync,
  managed events, deep-links, tests) and break the architecture contract.

The guide stays useful as a reference for scopes, endpoints, and error codes.

---

## 2. Current State (verified in code/config)

| Item | State |
|------|-------|
| Backend OAuth (`calendarService.js`, `calendarController.js`) | Complete |
| Callback routes (`/api/calendar/google/callback`, `/oauth/callback`) | Present |
| Mobile connect (`getCalendarConnectUrl` + `launchUrl`) | Present |
| Android deep-link `rakanstudent://calendar-success` / `calendar-error` | Present |
| Calendar consent screen | Reached (works) |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` / `GOOGLE_CALENDAR_REDIRECT_URI` | Set |
| `SUPABASE_SERVICE_ROLE_KEY` | Set |
| `GOOGLE_OAUTH_STATE_SECRET` | NOT set (falls back to service-role key) |
| Public URL | Rotating ngrok free domain (root cause of churn) |
| Debug log of redirect URI | Present at `calendarService.js:137` |

---

## 3. Root Problems to Solve (Calendar)

1. **Rotating ngrok URL** forces re-registering the redirect URI on every restart.
2. **`GOOGLE_OAUTH_STATE_SECRET` not explicit** — relies on a fallback secret.
3. **Leftover debug logging** of the redirect URI in `calendarService.js`.

> Drive `redirect_uri_mismatch` is intentionally **out of scope** for now.

---

## 4. Phased Plan

### Phase 1 — Stabilize the public URL (highest value)
- Choose ONE stable HTTPS endpoint:
  - Reserved **ngrok** domain (free tier allows one permanent domain), or
  - **Cloudflare Tunnel** (free permanent subdomain), or
  - Deploy backend to **Render / Railway / Fly.io** free tier.
- Set the stable URL once so redirect URIs are registered in Google only once.

### Phase 2 — Google Cloud Console (one-time)
- Enable **Google Calendar API**.
- OAuth client → Authorized redirect URIs (exact match, no trailing slash):
  - `https://<stable-domain>/api/calendar/google/callback`
  - `https://<stable-domain>/api/calendar/oauth/callback` (backup)
- OAuth consent screen:
  - Add scope `https://www.googleapis.com/auth/calendar`.
  - Add your Google account as a **Test user**.
  - Keep status **Testing** — the "Google hasn't verified this app" warning is
    expected; proceed via **Advanced → Continue**.

### Phase 3 — Backend env hardening
- `.env`: set `GOOGLE_CALENDAR_REDIRECT_URI` to the stable URL.
- `.env`: set an explicit `GOOGLE_OAUTH_STATE_SECRET` (random 32+ char string).
- Remove the debug `console.log('DEBUG REDIRECT URI', ...)` at
  `calendarService.js:137`.
- Run `npm run readiness` to confirm `validateCalendarConfig()` passes.

### Phase 4 — End-to-end verification (physical device)
- Profile → Connect Google Calendar → consent → returns via
  `rakanstudent://calendar-success`.
- Confirm a `calendar_connections` row exists with a **refresh_token**.
- Trigger a sync → confirm `calendar_busy_intervals` and
  `managed_schedule_events` populate.
- Confirm disconnect removes Google events + the DB row.

### Phase 5 — Optional UX polish
- Success/error toast on the profile screen after the deep-link returns.
- Surface `lastError` / `syncHealth` in the calendar status UI.

---

## 5. Open Decisions

| # | Decision | Default if unspecified |
|---|----------|------------------------|
| 1 | Hosting for the stable URL (laptop tunnel vs deploy) | Reserved ngrok domain |
| 2 | Capability scope: keep busy-sync + managed study blocks vs add full two-way event CRUD | Keep existing (busy-sync + managed blocks) |

---

## 6. Out of Scope (for this plan)
- Native `google_sign_in` rewrite.
- Google **Drive** OAuth fix (tracked separately, after Calendar).
- Publishing the app through Google's verification process.

---

## 7. Verification Commands

```powershell
cd C:\Users\USER\Downloads\student-task-orchestrator\student-task-orchestrator\backend
npm run readiness
npm test
```

---

## 8. Reference — Existing Flow (for maintainers)

```
Mobile (Profile -> Connect Google Calendar)
  | POST /api/calendar/connect-url   (Authorization: Bearer <supabase token>)
  v
Backend builds signed Google OAuth URL -> returns { url }
  | mobile launchUrl(externalApplication) opens browser
  v
User consents on Google
  | Google redirects to GOOGLE_CALENDAR_REDIRECT_URI
  v
Backend GET /api/calendar/google/callback
  | exchanges code -> stores tokens in calendar_connections
  | redirects to rakanstudent://calendar-success
  v
Mobile deep-link catches rakanstudent://calendar-success -> connected
```

Key files:
- `student-task-orchestrator/backend/lib/calendarService.js`
- `student-task-orchestrator/backend/controllers/calendarController.js`
- `student-task-orchestrator/backend/routes/calendar.js`
- `rakanstudent_mobile/lib/services/api_service.dart` (`getCalendarConnectUrl`)
- `rakanstudent_mobile/android/app/src/main/AndroidManifest.xml` (deep-link)
