# Rakan Student

Rakan Student is a student productivity platform for planning classes, tracking custom tasks, protecting focus time, and keeping learners accountable through reminders, analytics, and lightweight motivation loops. The current codebase contains a Flutter mobile client, a Node.js/Supabase backend, a React web dashboard, and supporting Python services for AI and optimization workflows.

The mobile app is the primary user-facing experience in this phase. It connects to Supabase for authentication and persistence, uses the Node.js API gateway for protected server workflows, and includes the newest Sprint Challenge mini-game as a short motivational break inside the dashboard experience.

## Tech Stack

### Mobile Client

- Flutter / Dart
- Supabase Flutter for authentication and direct Supabase access
- Riverpod-ready Flutter architecture
- `http` for API gateway calls
- `flutter_secure_storage` for persisted auth tokens
- `flutter_local_notifications` plus `timezone` for local task reminders
- `table_calendar` for calendar-style schedule views
- `image_picker` for future upload and capture flows

### Backend

- Node.js with Express 5
- Supabase JavaScript client
- PostgreSQL via Supabase
- Redis for readiness checks, queue support, and operational workflows
- Google Gemini SDK packages for AI routes
- Multer and CSV parser for ingestion/import flows
- Docker Compose support for the backend container

### Database & Infrastructure

- Supabase Auth
- Supabase Postgres
- Row Level Security policies across user-owned tables
- SQL migrations under `student-task-orchestrator/backend/supabase/migrations`
- Redis on `redis://127.0.0.1:6379`

### Additional Clients and Services

- React/Vite web client under `student-task-orchestrator/frontend`
- Python AI service under `student-task-orchestrator/ai_service`
- Python optimizer service under `student-task-orchestrator/optimizer-service`

## Repository Layout

```text
.
|-- README.md
|-- docker-compose.yml
|-- ARCHITECTURE.md
|-- rakanstudent_mobile/
|   |-- lib/
|   |   |-- core/
|   |   |-- features/
|   |   |-- models/
|   |   |-- screens/
|   |   |-- services/
|   |   `-- views/
|   |-- test/
|   `-- pubspec.yaml
`-- student-task-orchestrator/
    |-- backend/
    |   |-- controllers/
    |   |-- db/
    |   |-- lib/
    |   |-- middleware/
    |   |-- routes/
    |   |-- supabase/migrations/
    |   `-- server.js
    |-- frontend/
    |-- ai_service/
    `-- optimizer-service/
```

## Core Features

### Authentication

- Supabase email/password authentication.
- Access tokens are persisted in secure storage on mobile.
- The API service refreshes expiring Supabase sessions before protected calls.
- Backend routes are guarded by auth middleware and request-scoped Supabase clients.

### Fixed Classes / Schedule

- Students can store fixed weekly classes in Supabase.
- Classes include day of week, start time, end time, class name, and class type.
- Mobile schedule UI reads from the backend/Supabase and renders class cards with day and type chips.
- Dashboard uses today's fixed classes to surface the next class and schedule context.
- Database constraints enforce valid day codes and start-before-end time windows.

### Custom Tasks

- Students can create and view custom tasks.
- Tasks support title, status, type, due dates, estimated minutes, priority metadata, notes, and category links.
- The mobile task list fetches tasks through the API gateway and schedules local reminders after loading.
- Task mutation notifications refresh dashboard/task state after create/update flows.
- Backend task routes support the newer task architecture and Supabase-backed persistence.

### Focus Mode Timer

- Dashboard includes a focus timer with 15, 25, and 50 minute presets.
- Focus duration and focus streak are persisted in `user_preferences`.
- Completing a focus session increments the user's focus streak.
- Timer lifecycle is protected with mounted checks and cancellation during disposal.

### Notification Jobs / Queue

- Users can create reminders for tasks from the mobile task list.
- Reminder jobs are stored in Supabase through the backend analytics/notification flow.
- Backend notification dispatch loop starts with the server and processes scheduled reminder jobs.
- Notification preferences support inbox/email settings, lead time, quiet hours, and timezone.
- Redis readiness is checked as part of backend operational health.
- Local mobile notifications are also scheduled for fetched tasks.

### Sprint Challenge Mini-Game

- New Flutter mini-game screen: `SprintGameScreen`.
- The player changes lanes by tapping left or right.
- Obstacles spawn in lanes, speed increases over time, and score increments as obstacles are avoided.
- Collision triggers haptics and a polished game-over dialog.
- The implementation cancels timers safely, checks widget lifecycle state, and supports restart after crash.

### Dashboard & Analytics

- Dashboard shows active reminders, pending tasks, next class, focus streak, and focus controls.
- Analytics data is loaded from `/api/analytics/overview`.
- Backend supports streak snapshots, completion events, badges, notification preferences, and reminder job summaries.

### Workspaces, Calendar, and AI Routes

- Backend exposes routes for workspaces, calendar integration, orchestration, pipeline ingestion, settings, analytics, tasks, schedule, and AI chat.
- Google Calendar OAuth callback routes are registered.
- Calendar sync and notification loops start when the backend server boots.
- AI and optimizer services exist as supporting services, with the optimizer documented to run on port `8002`.

## Backend API Summary

The Express server starts on port `5000` and exposes:

- `GET /api/health` - basic backend health check.
- `GET /api/health/readiness` - Supabase, Redis, and integration readiness report.
- `GET /api/health/metrics` - operational metrics snapshot.
- `GET /api/health/supabase` - Supabase heartbeat.
- `/api/tasks` - task CRUD and task engine routes.
- `/api/schedule` - fixed class and schedule routes.
- `/api/calendar` - Google Calendar connection and sync routes.
- `/api/orchestration` - orchestration run/event workflows.
- `/api/analytics` - streaks, reminders, badges, and productivity summaries.
- `/api/workspaces` - collaborative workspace routes.
- `/api/settings` - user settings routes.
- `/api/pipeline` - ingestion pipeline routes.
- `/api/ai` - AI chat/action routes.

## Database Schema Summary

Schema is managed through Supabase migrations in:

```text
student-task-orchestrator/backend/supabase/migrations/
```

### Auth and User Tables

- `users` - legacy/local user identity table with unique email.
- `user_profiles` - wake/sleep times, meal windows, transit buffer, and life schedule settings.
- `user_preferences` - mobile preference storage used for focus duration and focus streak.

### Task Tables

- `primary_tasks` - imported or AI-generated high-level tasks.
- `sub_tasks` - decomposed task units with scheduling windows and ownership.
- `tasks` - newer core task engine table for custom tasks.
- `categories` - user-owned task categories with validated color hex values.
- `tags` - user-owned tags.
- `task_tags_map` - join table connecting tags to either `tasks` or `primary_tasks`.
- `ingest_pipeline_runs` - tracks document/import pipeline status and idempotency.

### Schedule Tables

- `fixed_classes` - weekly fixed class schedule with day, start/end time, class name, class type, user ownership, RLS, and time validity constraints.
- `calendar_connections` - Google Calendar connection state and tokens.
- `calendar_calendars` - discovered external calendars.
- `calendar_busy_intervals` - busy windows from connected calendars.
- `managed_schedule_events` - app-managed scheduled task events.

### Orchestration Tables

- `orchestration_runs` - execution state for AI/task orchestration runs.
- `orchestration_events` - event log for orchestration lifecycle.
- `orchestration_chunk_results` - per-chunk outputs from orchestration processing.

### Collaboration and Analytics Tables

- `workspaces` - collaborative workspace records and invite codes.
- `workspace_members` - workspace membership with role/status constraints.
- `workspace_tasks` - workspace-to-sub-task links.
- `workspace_activity_events` - activity stream for collaboration.
- `completion_events` - task completion history.
- `productivity_daily_stats` - per-user daily productivity aggregates.
- `workspace_productivity_stats` - per-workspace daily productivity aggregates.
- `streak_snapshots` - per-user streak records.
- `badges` - badge definitions.
- `user_badges` - awarded badges.

### Notification Tables

- `notification_preferences` - inbox/email/push preferences, quiet hours, lead minutes, and timezone.
- `web_push_subscriptions` - browser push subscription endpoints.
- `reminder_jobs` - scheduled reminders with channel/status checks.
- `reminder_deliveries` - delivery attempts and states for each reminder/channel pair.

## Important Constraints and Database Guarantees

- `fixed_classes.day_of_week` accepts `MON`, `TUE`, `WED`, `THU`, `FRI`, `SAT`, `SUN`.
- `fixed_classes.start_time` must be earlier than `end_time`.
- `tasks.priority_level` is constrained to `Low`, `Medium`, or `High`.
- `tasks.status` was expanded for the newer architecture to support lowercase task lifecycle states.
- `task_type` constraints were added for both `tasks` and `primary_tasks`.
- Category and tag names are unique per user.
- Reminder channels are constrained to `inbox`, `email`, or `push`.
- Reminder statuses are constrained to `scheduled`, `sent`, `dismissed`, `cancelled`, or `failed`.
- Delivery uniqueness prevents duplicate reminder delivery rows for the same reminder/channel.
- Completion event uniqueness prevents duplicate task completion records.
- Workspace membership and workspace task links have uniqueness constraints.
- Subtasks now carry explicit `user_id` ownership.

## Recent Updates

### Mobile Lifecycle Fixes

- Added `mounted` and `context.mounted` checks across async UI flows.
- Protected navigation, dialogs, snackbars, and `setState` calls after awaited operations.
- Cancelled timers in `dispose` for focus mode and Sprint Challenge game loops.
- Hardened bottom-sheet and dialog flows so async returns do not update disposed widgets.

### Layout and Overflow Fixes

- Added text truncation and wrapping for long task, class, profile, and dashboard labels.
- Used `Expanded`, `Wrap`, and max-line handling in dense cards.
- Improved class cards, dashboard sections, and auth screens to stay stable on smaller devices.
- Polished dashboard cards and task list interactions for mobile viewport constraints.

### Database and Constraint Updates

- Added fixed class schedule persistence with RLS and day/time validation.
- Added notification preference, reminder job, reminder delivery, and web push tables.
- Added unique indexes for reminder deliveries, completion events, workspace invite codes, task ingestion keys, and task tags.
- Added task taxonomy tables for categories, tags, and task-tag mapping.
- Added task architecture columns such as status, task type, category, due date, notes, and subtask user ownership.
- Added timezone support to notification preferences.

### Backend Operational Updates

- Backend now exposes readiness and metrics health endpoints.
- Server starts calendar sync and notification dispatch loops on boot.
- Request context and auth middleware are applied across protected API routes.
- Supabase DNS is checked during startup before accepting backend traffic.
- Redis readiness is included in operational health checks.

### Sprint Challenge Mini-Game

- Added a self-contained Flutter lane-dodging mini-game.
- Added score, increasing speed, collision detection, haptics, blur-backed game-over dialog, and restart behavior.
- Integrated lifecycle guards so timers stop when the screen is removed.

## Local Development

### Backend

```powershell
cd student-task-orchestrator\backend
npm install
npm run dev
```

Backend default:

```text
http://127.0.0.1:5000/api
```

Health check:

```powershell
Invoke-WebRequest http://127.0.0.1:5000/api/health
```

Readiness:

```powershell
npm run readiness
```

### Flutter Mobile

```powershell
cd rakanstudent_mobile
flutter pub get
flutter run
```

The mobile app expects Supabase and backend configuration through its `.env` file.

### React Web Client

```powershell
cd student-task-orchestrator\frontend
npm install
npm run dev -- --host 127.0.0.1 --port 5174
```

Default local web route:

```text
http://127.0.0.1:5174/signin
```

### Redis

If Redis is not already running:

```powershell
docker run -d --name sto-redis -p 6379:6379 redis:7-alpine
```

If the container already exists:

```powershell
docker start sto-redis
```

### Optimizer Service

```powershell
cd student-task-orchestrator\optimizer-service
.\venv\Scripts\Activate.ps1
python -m uvicorn app.main:app --host 127.0.0.1 --port 8002 --reload
```

### AI Service

```powershell
cd student-task-orchestrator\ai_service
.\venv\Scripts\Activate.ps1
python -m uvicorn main:app --host 127.0.0.1 --port 8001 --reload
```

Important: the project startup guide standardizes the Python services on Python 3.12. Some AI dependencies do not install cleanly on newer Python versions.

## Environment Variables

### Backend

Backend env file:

```text
student-task-orchestrator/backend/.env
```

Important variables:

- `PORT`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `GEMINI_API_KEY`
- `REDIS_URL`
- `FRONTEND_BASE_URL`
- `APP_TIMEZONE`
- `GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET`
- `GOOGLE_CALENDAR_REDIRECT_URI`
- `GOOGLE_OAUTH_STATE_SECRET`
- `ERROR_TRACKING_WEBHOOK_URL`
- `NOTIFICATION_EMAIL_WEBHOOK_URL`
- `RESEND_API_KEY`
- `RESEND_FROM_EMAIL`
- `NOTIFICATION_PUSH_WEBHOOK_URL`
- `VAPID_PUBLIC_KEY`
- `VAPID_PRIVATE_KEY`

### Flutter Mobile

Mobile env file:

```text
rakanstudent_mobile/.env
```

The mobile client needs Supabase credentials and the API base URL expected by `EnvConfig`.

### React Web

Frontend env files:

```text
student-task-orchestrator/frontend/.env
student-task-orchestrator/frontend/.env.local
```

Common variables:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`
- `VITE_WEB_PUSH_PUBLIC_KEY`

## Verification Commands

### Backend Tests

```powershell
cd student-task-orchestrator\backend
npm test
```

### Backend Readiness

```powershell
cd student-task-orchestrator\backend
npm run readiness
```

### Flutter Tests

```powershell
cd rakanstudent_mobile
flutter test
```

### Frontend Build

```powershell
cd student-task-orchestrator\frontend
npm run build
```

## Current Known Notes

- The active mobile application is `rakanstudent_mobile`.
- The backend server is the main API gateway and runs on port `5000`.
- The React frontend is still present and useful for web dashboard work, but the requested feature summary is centered on Flutter mobile plus Node/Supabase backend.
- Python AI service dependencies should be installed with Python 3.12.
- If reminder dispatch logs mention missing `reminder_deliveries`, apply the Supabase migrations and refresh the Supabase schema cache.
- Redis must be reachable for full backend readiness.
