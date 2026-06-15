# Google Calendar API Integration — Implementation Plan

> Status: PLAN (not yet executed)
> Model: Server-side OAuth (existing architecture) — NOT the native client-side model
> Scope: Harden & finish the working Calendar integration; fix Drive separately

## 1. Decision: Keep the Server-Side Model

The shared guide describes a **native client-side** flow (`google_sign_in` +
`googleapis` on-device). This project already implements the **server-side**
flow end-to-end, and Calendar already reaches Google's consent screen.

Keep server-side because:
- It already works (reached consent; refresh-token + sync logic complete).
- `TASK_DOCUMENT.md` requires clients to talk only to the backend and hold no
  provider secrets.
- Switching to native would discard working code (token refresh, busy-sync,
  managed events, deep-links, tests) and violate the architecture contract.

The guide remains a useful reference for scopes, endpoints, and error codes.

## 2. Current State (verified)

| Item | State |
|------|-------|
| Backend OAuth (`calendarService.js`, `calendarController.js`) | Complete |
| Callback routes (`/api/calendar/google/callback`, `/oauth/callback`) | Present |
| Mobile connect (`getCalendarConnectUrl` + `launchUrl`) | Present |
| Android deep-link `rakanstudent://calendar-success|error` | Present |
| Calendar consent screen | Reached (works) |
| `GOOGLE_CLIENT_ID/SECRET`, `GOOGLE_CALENDAR_REDIRECT_URI` | Set |
| `SUPABASE_SERVICE_ROLE_KEY` | Set |
| `GOOGLE_OAUTH_STATE_SECRET` | NOT set (falls back to service-role key) |
| Public URL | Rotating ngrok free domain (root cause of churn) |
| Debug log of redirect URI | Present at `calendarService.js:137` |

## 3. Root Problems to Solve

1. **Rotating ngrok URL** forces re-registering redirect URIs every restart.
2. **`GOOGLE_OAUTH_STATE_SECRET` not explicit** — relies on a fallback.
3. **Leftover debug logging** of the redirect URI.
4. (Separate track) **Drive `redirect_uri_mismatch`** — out of scope here.

## 4. Phased Plan

### Phase 1 — Stabilize the public URL (highest value)
- Choose ONE: reserved ngrok domain (free tier allows 1), Cloudflare Tunnel,
  or deploy backend (Render/Railway/Fly free tier).
- Set the stable HTTPS URL once; register redirect URIs in Google once.

### Phase 2 — Google Cloud Console (one-time)
- Enable **Google Calendar API**.
- OAuth client → Authorized redirect URIs (exact, no trailing slash):
  - `https://<stable-domain>/api/calendar/google/callback`
  - `https://<stable-domain>/api/calendar/oauth/callback` (backup)
- OAuth consent screen: add scope `.../auth/calendar`; add your Google account
  as a **Test user**; keep status **Testing** (the "unverified" warning is
  expected — Advanced → Continue).

### Phase 3 — Backend env hardening
- `.env`: set `GOOGLE_CALENDAR_REDIRECT_URI` to the stable URL.
- `.env`: set an explicit `GOOGLE_OAUTH_STATE_SECRET` (random 32+ char string).
- Remove debug `console.log` at `calendarService.js:137`.
- Run `npm run readiness` → confirm `validateCalendarConfig()` passes.

### Phase 4 — End-to-end verification (physical device)
- Profile → Connect → consent → returns via `rakanstudent://calendar-success`.
- Confirm `calendar_connections` row has a **refresh_token**.
- Trigger sync → `calendar_busy_intervals` / `managed_schedule_events` populate.
- Confirm disconnect cleans up Google events + DB row.

### Phase 5 — Optional UX polish
- Success/error toast on the profile screen after deep-link return.
- Surface `lastError` / `syncHealth` in the calendar status UI.

## 5. Open Decisions (need user input)
1. Hosting for the stable URL: laptop tunnel vs deploy?
2. Drive: fix now or defer? (separate plan)
3. Capability: keep busy-sync + managed study blocks (built), or also add
   full two-way event CRUD from the app (guide-style)?

## 6. Out of Scope
- Native `google_sign_in` rewrite.
- Drive OAuth fix (tracked separately).
- Publishing the app for Google verification.

## 7. Verification Commands
```powershell
cd C:\Users\USER\Downloads\student-task-orchestrator\student-task-orchestrator\backend
npm run readiness
npm test