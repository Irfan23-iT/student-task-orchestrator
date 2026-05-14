# RakanStudent Unified Task Document

## 1. Final Vision

RakanStudent is a multi-client academic orchestration platform for students who need one trusted system to understand their workload, protect their time, and help them act. The finished product should feel like a capable study operations assistant: it authenticates the student, ingests tasks and academic context, decomposes large goals into actionable work, schedules that work around real-life constraints, tracks progress, supports collaboration, and uses AI proactively when the user asks for help.

The final experience should be available from:

- A Flutter mobile app for the primary student experience.
- A React web dashboard for richer desktop workflows.
- A Node.js backend API that is the official client-facing contract.
- Python AI and optimizer services that perform specialized orchestration work behind the backend.
- Supabase Auth and Postgres as the system of record.

The system should not simply tell students what to do. When the user gives a planning intent, deadline, class schedule, exam, assignment, or reminder request, RakanStudent should convert that intent into persisted tasks, schedule blocks, reminders, and clear next steps while respecting authentication, privacy, local calendar constraints, and user preferences.

## 2. Product Context

Students often keep academic obligations in scattered places: syllabi, PDFs, class schedules, group chats, calendars, and memory. RakanStudent is intended to centralize those inputs and turn them into a practical plan.

The current repository already contains:

- A Flutter mobile client in `rakanstudent_mobile/`.
- A React web client in `student-task-orchestrator/frontend/`.
- A Node.js API gateway in `student-task-orchestrator/backend/`.
- A Python AI service in `student-task-orchestrator/ai_service/`.
- A Python optimizer service in `student-task-orchestrator/optimizer-service/`.
- Supabase migrations and backend tests for auth, tasks, analytics, notifications, calendar, workspaces, and orchestration.

The mobile app is the key end-user surface. It should follow the existing backend handoff: authenticate with Supabase on-device, retrieve the Supabase access token, and call only the Node backend under `/api/...` with `Authorization: Bearer <access_token>`. The mobile app must not call the Python services directly and must not ship backend secrets.

The web app remains a reference implementation and desktop companion. The backend is the integration point shared by both clients.

## 3. Target Users

Primary user:

- A student managing classes, assignments, study sessions, exams, reminders, and group work.

Secondary users:

- Teammates in workspace collaboration rooms.
- Developers or reviewers validating the capstone implementation.
- Future maintainers extending the backend, mobile app, or AI services.

The product should support both fresh accounts with no data and active student accounts with tasks, fixed classes, reminders, analytics history, calendar status, and workspace memberships.

## 4. Operating Principles

- The Node backend is the official mobile and web API surface.
- Supabase Auth issues the session token; the backend verifies it before protected work.
- Supabase Postgres is the system of record.
- Row Level Security and backend user filters must prevent cross-account access.
- Clients must not contain service-role keys, AI provider keys, OAuth client secrets, VAPID private keys, webhook URLs, or email provider secrets.
- AI features must be useful, structured, and action-oriented rather than passive.
- All backend errors should preserve enough context for debugging, especially `x-request-id` when present.
- The mobile app should favor feature-first architecture with repositories, Riverpod providers, shared core networking, shared errors, and widgets that do not call HTTP directly.
- No new dependencies should be introduced unless they are explicitly needed and approved.

## 5. System Architecture

### 5.1 Components

Flutter mobile client:

- Native student experience for authentication, dashboard, tasks, AI chat, schedule, calendar, profile, analytics, reminders, and workspaces.
- Uses Supabase Auth locally.
- Sends backend requests with bearer tokens.

React web client:

- Browser dashboard for context ingest, task orchestration, analytics, workspaces, settings, and richer desktop workflows.
- Uses the same auth and backend pattern.

Node.js API gateway:

- Owns authenticated REST routes.
- Validates requests.
- Applies account-state checks.
- Persists tasks, profile settings, schedules, reminders, workspace state, analytics, pipeline state, and orchestration runs.
- Exposes health, readiness, and metrics endpoints.
- Calls or coordinates AI and optimizer services as needed.

Python AI service:

- Handles specialized AI execution such as assignment breakdown, syllabus parsing, timetable extraction, and schedule generation.
- Should return structured, normalized output for persistence.

Python optimizer service:

- Applies scheduling and local-context optimization logic.
- Must not be called directly from mobile clients.

Supabase:

- Provides Auth and Postgres persistence.
- Enforces table-level Row Level Security.
- Stores users, tasks, subtasks, pipeline runs, profiles, fixed classes, analytics, reminders, badges, workspaces, calendar integrations, and orchestration state.

### 5.2 High-Level Flow

1. The user signs in or signs up through Supabase from Flutter or React.
2. The client receives a Supabase session and access token.
3. The client calls the Node backend with `Authorization: Bearer <access_token>`.
4. Backend middleware verifies the token and attaches authenticated user context.
5. Standard CRUD endpoints read and write Supabase.
6. AI flows create orchestration records or call AI services through backend-owned logic.
7. Normalized results are persisted to Supabase.
8. Mobile and web clients render the updated state from backend API responses.

## 6. Authentication and Security Requirements

### 6.1 Authentication

- Current auth is email/password through Supabase.
- Every protected backend call must include `Authorization: Bearer <supabase_access_token>`.
- Public endpoints are limited to health/readiness/metrics/Supabase health and calendar OAuth callbacks.
- On `401`, clients should refresh the Supabase session once, retry the request once, then sign out if refresh fails.
- On account access blocks, clients should show an explicit blocked-account state.

### 6.2 Backend Authorization

- Backend routes must use request-scoped authenticated context.
- Protected endpoints must reject missing or invalid tokens with `401`.
- Disabled, banned, or revoked sessions must be blocked.
- Backend write paths must apply user ownership filters even when RLS should also protect the table.
- Workspace task assignment must require an active workspace membership for the assignee.
- Reminder creation must verify that the referenced subtask belongs to the authenticated user.
- Pipeline state upserts must verify ownership before accepting caller-supplied run IDs.
- Push subscription endpoints must reject endpoint reuse across users.

### 6.3 Data Security

- Supabase RLS must be enabled for user-owned and collaboration-scoped tables.
- Users must be able to access only their own tasks, profiles, reminders, analytics, calendar connections, and permitted workspace records.
- Client apps may contain only public Supabase URL, public anon key, and API base URL.
- Service-role, Gemini, Google client secret, VAPID private key, Resend, and webhook secrets must remain backend-only.

## 7. Environment Requirements

### 7.1 Local Prerequisites

- Python 3.12.
- Node.js 20 or newer.
- Docker or local Redis for backend queue/readiness support.
- Flutter SDK for mobile development.
- Supabase project credentials.
- Gemini or Google AI key for AI flows.
- Optional integrations: Google Calendar OAuth, Resend or email webhook, push/VAPID configuration, and error tracking webhook.

### 7.2 Local Service Ports

- Node backend: `5000`.
- AI service: `8001`.
- Optimizer service: `8002`.
- React frontend: `5174`.
- Redis: `6379`.

### 7.3 Mobile Local URLs

- Android emulator backend: `http://10.0.2.2:5000/api`.
- iOS simulator backend: `http://127.0.0.1:5000/api`.
- Physical device backend: `http://<local-lan-ip>:5000/api`.

### 7.4 Required Mobile Environment Keys

- `MOBILE_API_BASE_URL`.
- `MOBILE_SUPABASE_URL`.
- `MOBILE_SUPABASE_ANON_KEY`.

## 8. Feature Requirements

### 8.1 Authentication and Account Entry

Functional requirements:

- Provide sign-in and sign-up screens in the mobile app.
- Use Supabase Auth for email/password sessions.
- Preserve the session securely.
- Gate protected app surfaces behind an authenticated state.
- Show clear loading, error, and signed-out states.
- Support sign-out.

Acceptance criteria:

- A valid user can sign in and reach the app shell.
- A new user can sign up and reach the app shell after Supabase accepts the account.
- Invalid credentials produce a clear error.
- Expired sessions refresh once before forcing re-authentication.
- Protected backend calls include the bearer token.

### 8.2 Dashboard

Functional requirements:

- Show a high-signal student dashboard after authentication.
- Summarize pending tasks, upcoming schedule blocks, next class, reminders, workspace activity, and profile readiness.
- Handle empty states gracefully.
- Support pull-to-refresh or equivalent refresh behavior.
- Invalidate or refresh dashboard data after task mutations.

Acceptance criteria:

- Fresh accounts see useful empty states, not broken UI.
- Accounts with tasks show task counts, titles, status, priority, schedule labels, and estimated time.
- Backend failures show actionable errors with retry affordances.

### 8.3 Core Task Engine

Functional requirements:

- Persist user-owned tasks and subtasks in Supabase.
- Support task creation, retrieval, deletion, and completion updates.
- Support flat task rows for mobile scheduling and dashboard UI.
- Support primary task groups with nested subtasks.
- Support run-scoped task results from AI or ingest pipelines.
- Support CSV import through backend.
- Preserve priority band, priority score, priority reason, estimated minutes, status, schedule date, start time, end time, pipeline run ID, client task key, and primary task ID where available.

Backend requirements:

- `GET /api/tasks` retrieves tasks for the authenticated user.
- `POST /api/tasks` creates a task for the authenticated user.
- `GET /api/tasks/rows` retrieves flat task rows.
- `GET /api/tasks/runs/:runId` retrieves saved task rows for a run.
- `POST /api/tasks/save-run` persists decomposition results.
- `PATCH /api/tasks/subtasks/:id` marks subtasks complete or incomplete.
- `DELETE /api/tasks/session` deletes session-created tasks.
- `DELETE /api/tasks` deletes all tasks for the current user.
- `POST /api/tasks/import` imports tasks from CSV using multipart field `file`.

Database requirements:

- User-owned task rows must include `user_id`.
- RLS policies must limit select, insert, update, and delete operations to the owning user.
- Parent task status synchronization must remain user-scoped.

Acceptance criteria:

- A user can create a task from mobile and then see it in the mobile task list.
- A user can fetch task rows from mobile.
- A user can complete and uncomplete a subtask.
- A malformed create request returns a 400-level response, not a crash.
- A user cannot access or mutate another user's tasks.

### 8.4 AI Chat and Orchestrator

Functional requirements:

- Provide an AI chat surface in mobile.
- Preserve local chat history during the view session.
- Send chat prompts to backend AI endpoints, not directly to AI providers.
- Backend AI chat must load the user's current active task context before prompting the LLM.
- AI responses should be context-aware and able to answer questions such as "What do I have to do today?"
- Goal orchestration should break broad academic goals into actionable generated tasks.
- The AI must be proactive when the user implies a planning, scheduling, reminder, exam, assignment, or upcoming-event need.

Strict action requirements:

- The system prompt should define the AI as an autonomous executive assistant with database write capability.
- The AI must not tell the user to manually do work that the system can do.
- The AI must emit an `ACTION: {"type":"CREATE_TASK","data":{...}}` block when the user asks to plan, schedule, remind, or gives an upcoming event that should become a task.
- The backend parser must handle a response containing both a natural-language confirmation and an action block.
- Forbidden behavior includes telling the user "Add this to your list", "To get started, create a task", or "Make sure to schedule" when an action can be performed.

Backend requirements:

- `POST /api/ai/chat` accepts a user message and returns a text AI response.
- `POST /api/ai/orchestrate` accepts a goal and returns generated task objects.
- AI controller logic must use request-scoped user context.
- AI controller tests must cover prompt/action enforcement and parser behavior.

Acceptance criteria:

- The user can ask "What do I have to do today?" and receive a response based on stored tasks.
- The user can say "i have a math exam on friday help me plan my study session for it tomorrow morning" and the AI creates a task without asking the user to manually add it.
- The response confirms what was scheduled in natural language.
- The created task appears in Supabase and in the mobile task list for the authenticated user.

### 8.5 Schedule and Fixed Classes

Functional requirements:

- Store profile scheduling preferences such as wake time, sleep time, meals, and transit buffers.
- Store recurring fixed classes.
- Show schedule data in mobile.
- Persist generated schedule rows against logical task IDs.
- Respect local context such as prayer shields, Friday Jumu'ah lockout, Friday/Saturday weekend behavior, and week-start expectations where optimizer logic applies.
- Support schedule rebuild orchestration.

Backend requirements:

- `GET /api/settings/profile` loads schedule/profile settings.
- `PUT /api/settings/profile` saves schedule/profile settings.
- `GET /api/settings/readiness` returns system readiness.
- `GET /api/calendar/fixed-classes` loads recurring fixed classes.
- `POST /api/calendar/fixed-classes/bulk` saves fixed classes in bulk.
- `POST /api/schedule/persist` persists schedule rows.

Acceptance criteria:

- A user can save profile schedule settings.
- A user can create fixed classes and see them after refresh.
- Schedule rows persist to the backend and remain scoped to the user.

### 8.6 Calendar Integration

Functional requirements:

- Show whether Google Calendar is connected.
- Generate a backend-owned Google OAuth connect URL.
- Sync external busy intervals.
- Rebuild app-managed calendar events.
- Disconnect calendar integration.
- Keep OAuth secrets backend-only.

Backend requirements:

- `GET /api/calendar/status`.
- `POST /api/calendar/connect-url`.
- `POST /api/calendar/sync`.
- `POST /api/calendar/rebuild`.
- `DELETE /api/calendar/connection`.
- Public callbacks: `/api/calendar/oauth/callback` and `/api/calendar/google/callback`.

Acceptance criteria:

- Mobile can display connected or disconnected state.
- Mobile can request a connect URL and open it.
- Calendar sync failures produce clear errors.
- App-managed calendar actions never expose Google client secrets to mobile.

### 8.7 Analytics, Reminders, and Notifications

Functional requirements:

- Load analytics overview for dashboard and profile surfaces.
- Track task completion events, daily productivity, streaks, badges, reminders, notification preferences, delivery capabilities, and orchestration runs.
- Allow users to create reminders for their own subtasks.
- Allow users to mark reminders as read, dismissed, or otherwise updated by supported actions.
- Allow notification preferences to be saved.
- Support browser push subscription persistence for web.
- Mobile native push is out of scope unless explicitly added later.

Backend requirements:

- `GET /api/analytics/overview`.
- `PUT /api/analytics/preferences`.
- `POST /api/analytics/reminders`.
- `PATCH /api/analytics/reminders/:id`.
- `PUT /api/analytics/push-subscriptions`.
- `DELETE /api/analytics/push-subscriptions`.

Acceptance criteria:

- Analytics overview loads for authenticated users.
- Reminder creation verifies subtask ownership.
- Reminder updates affect only the authenticated user's reminder data.
- Notification preference changes persist.

### 8.8 Workspaces and Collaboration

Functional requirements:

- Users can create workspaces.
- Users can join workspaces with invite codes.
- Workspace owners or permitted roles can add members.
- Workspace roles and member status can be changed.
- Workspace tasks can be assigned only to active workspace members.
- Workspace overview should show workspaces, members, assignments, and activity.

Backend requirements:

- `GET /api/workspaces/overview`.
- `POST /api/workspaces`.
- `POST /api/workspaces/join`.
- `GET /api/workspaces/:id/share`.
- `POST /api/workspaces/:id/members`.
- `PATCH /api/workspaces/:id/members/:memberUserId`.
- `POST /api/workspaces/:id/tasks`.

Acceptance criteria:

- A user can create a workspace from mobile.
- A user can join a workspace by invite code.
- Invite codes can be generated or retrieved.
- Assignments fail if the assignee is not an active workspace member.

### 8.9 Orchestration Runs and Pipeline State

Functional requirements:

- Support async AI/orchestration runs.
- Track run status, attempt count, payload, result payload, warnings, errors, events, and chunk results.
- Allow retry and cancellation of terminal or active runs where supported.
- Save resumable pipeline state.
- Load the latest pipeline state for resume flows.

Supported orchestration kinds:

- `assignment_breakdown`.
- `subtask_breakdown`.
- `schedule_rebuild`.
- `syllabus_parse`.
- `timetable_extract`.

Supported orchestration statuses:

- `QUEUED`.
- `PROCESSING`.
- `COMPLETED`.
- `COMPLETED_WITH_WARNINGS`.
- `FAILED`.
- `FAILED_TIMEOUT`.
- `CANCELLED`.

Backend requirements:

- `GET /api/orchestration/overview`.
- `POST /api/orchestration/runs`.
- `GET /api/orchestration/runs/:id`.
- `POST /api/orchestration/runs/:id/retry`.
- `POST /api/orchestration/runs/:id/cancel`.
- `POST /api/pipeline/state`.
- `GET /api/pipeline/state/latest`.

Acceptance criteria:

- Clients can create and poll orchestration runs.
- Failed runs can surface useful errors.
- Retry and cancel endpoints enforce ownership and valid transitions.
- Pipeline state cannot be upserted across accounts.

### 8.10 Web Client

Functional requirements:

- Continue to support the React dashboard as a desktop companion.
- Use Supabase Auth in browser.
- Send the same backend bearer token.
- Keep local frontend URL as `http://127.0.0.1:5174` for verified development.
- Maintain buildability with `npm run build`.

Acceptance criteria:

- `/signin` renders the RakanStudent sign-in form.
- `/` redirects to sign-in or renders the authenticated app shell.
- Production build succeeds.

## 9. API Contract Summary

Public endpoints:

- `GET /api/health`.
- `GET /api/health/readiness`.
- `GET /api/health/metrics`.
- `GET /api/health/supabase`.
- `GET /api/calendar/oauth/callback`.
- `GET /api/calendar/google/callback`.

Protected endpoint groups:

- Tasks: `/api/tasks/...`.
- Settings: `/api/settings/...`.
- Schedule: `/api/schedule/...`.
- Pipeline: `/api/pipeline/...`.
- Analytics and notifications: `/api/analytics/...`.
- Calendar: `/api/calendar/...`.
- Orchestration: `/api/orchestration/...`.
- Workspaces: `/api/workspaces/...`.
- AI: `/api/ai/...`.

Authentication contract:

- Mobile and web clients authenticate with Supabase Auth.
- Protected backend requests must include `Authorization: Bearer <supabase_access_token>`.
- The Node backend validates the Supabase JWT and derives the user from the request.
- Clients must not call Python services directly.
- Clients must not hold backend service-role keys, Google OAuth secrets, AI provider keys, Redis credentials, or database passwords.

Canonical local URLs:

- Web backend: `http://localhost:5000/api`.
- Android emulator backend: `http://10.0.2.2:5000/api`.
- iOS simulator backend: `http://127.0.0.1:5000/api`.
- Physical-device backend: `http://<local-LAN-IP>:5000/api`.
- Frontend dev server: `http://127.0.0.1:5174`.
- Google Calendar callback: `http://localhost:5000/api/calendar/google/callback`.

Canonical task routes:

- `GET /api/tasks`
  - Current repo contract: returns direct/manual `tasks` rows for the authenticated user.
  - Response: `{ "tasks": [{ "id": "...", "title": "...", "description": "...", "due_date": "YYYY-MM-DD", "priority_level": "Medium", "status": "Pending" }] }`.
- `POST /api/tasks`
  - Request: `{ "title": "...", "description": "...", "due_date": "YYYY-MM-DD", "priority_level": "Low|Medium|High" }`.
  - Response: `{ "task": { "id": "...", "title": "...", "status": "Pending" } }`.
- `GET /api/tasks/rows`
  - Response: `{ "rows": [{ "id": "...", "parent_task_id": "...", "title": "...", "estimated_minutes": 45, "status": "pending", "is_chunked": false, "scheduled_date": "YYYY-MM-DD", "scheduled_start_time": "09:00", "scheduled_end_time": "09:45", "pipeline_run_id": "...", "client_task_key": "...", "primary_task_id": "...", "priority_score": 78, "priority_band": "high", "priority_reason": "...", "manual_priority_override": false, "user_id": "..." }] }`.
- `GET /api/tasks/runs/:runId`
  - Response returns generated task rows for the authenticated user's pipeline run.
- `POST /api/tasks/save-run`
  - Request: `{ "runId": "...", "courseTitle": "Computer Science", "tasks": [{ "title": "Read chapter 1", "duration": 45, "priority_band": "medium", "priority_reason": "Due soon" }] }`.
  - Response: `{ "primaryTaskId": "...", "rows": [{ "id": "...", "title": "...", "estimated_minutes": 45, "priority_band": "medium", "priority_reason": "...", "primary_task_id": "...", "pipeline_run_id": "..." }] }`.
- `PATCH /api/tasks/subtasks/:id`
  - Request: `{ "completed": true }`.
  - Response: `{ "subTask": { "id": "...", "status": "completed" } }`.
- `DELETE /api/tasks/session`
  - Request: `{ "primaryTaskIds": ["..."], "subTaskIds": ["..."], "pipelineRunId": "..." }`.
  - Response: `{ "success": true }`.
- `DELETE /api/tasks`
  - Deletes authenticated user's task data according to the backend controller contract.
- `POST /api/tasks/import`
  - Request: multipart form-data CSV file field named `file`.
  - Response: `{ "message": "...", "details": [{ "row": 1, "status": "imported" }] }`.

Canonical settings routes:

- `GET /api/settings/profile`
  - Response: `{ "storageMode": "remote", "settings": { "wakeTime": "07:00", "sleepTime": "23:30", "breakfastStart": "07:30", "breakfastEnd": "08:00", "lunchStart": "12:30", "lunchEnd": "13:30", "dinnerStart": "19:00", "dinnerEnd": "20:00", "transitBufferMinutes": 20 } }`.
- `PUT /api/settings/profile`
  - Request uses the same settings fields shown above.
  - Response returns the persisted settings.
- `GET /api/settings/readiness`
  - Response reports profile/settings dependency readiness.

Canonical schedule and pipeline routes:

- `POST /api/schedule/persist`
  - Request: `{ "logicalTaskIds": ["..."], "scheduleRows": [{ "source_task_id": "...", "scheduled_date": "YYYY-MM-DD", "scheduled_start_time": "10:00", "scheduled_end_time": "10:45" }] }`.
  - Response: `{ "result": [{ "source_task_id": "...", "scheduled_date": "YYYY-MM-DD" }] }`.
- `POST /api/pipeline/state`
  - Request includes `id`, `user_id`, `phase`, `status`, `failed_phase`, `last_completed_phase`, `primary_task_id`, `logical_task_ids`, `optimizer_payload`, `schedule_rows`, `retry_counts`, `error_message`, `recoverable`, and `updated_at`.
  - Response: `{ "storageMode": "remote", "pipelineRun": { "id": "...", "phase": "...", "status": "..." } }`.
- `GET /api/pipeline/state/latest`
  - Response returns the latest persisted pipeline run state for the authenticated user.

Canonical analytics and reminder routes:

- `GET /api/analytics/overview`
  - Response includes `storageMode`, `completionEvents`, `reminderJobs`, `reminderDeliveries`, `notificationPreferences`, `pushSubscriptions`, `userBadges`, `badgeCatalog`, `productivityDailyStats`, `streakSnapshot`, `orchestrationRuns`, `tasks`, and `deliveryCapabilities`.
- `PUT /api/analytics/preferences`
  - Request: `{ "inboxEnabled": true, "emailEnabled": false, "reminderLeadMinutes": 15, "quietHoursStart": "22:00", "quietHoursEnd": "07:00", "timeZone": "Asia/Kuala_Lumpur" }`.
  - Response contains `notificationPreferences` in the backend persisted shape.
- `POST /api/analytics/reminders`
  - Request: `{ "subTaskId": "...", "title": "...", "reminderAt": "2026-05-09T09:00:00.000Z", "channel": "in_app" }`.
  - Response: `{ "reminder": { "id": "...", "sub_task_id": "...", "title": "...", "reminder_at": "...", "channel": "in_app" }, "delivery": { "id": "...", "status": "pending" } }`.
- `PATCH /api/analytics/reminders/:id`
  - Request: `{ "action": "read" }`.
  - Response: `{ "reminder": { "id": "...", "status": "read" }, "delivery": { "id": "...", "status": "read" } }`.
- `PUT /api/analytics/push-subscriptions`
  - Request: `{ "subscription": { "endpoint": "...", "keys": { "p256dh": "...", "auth": "..." } } }`.
  - Response: `{ "pushSubscription": { "endpoint": "..." } }`.
- `DELETE /api/analytics/push-subscriptions`
  - Deletes the authenticated user's push subscription.

Canonical calendar routes:

- `GET /api/calendar/status`.
- `POST /api/calendar/connect-url`.
- `POST /api/calendar/sync`.
- `POST /api/calendar/rebuild`.
- `DELETE /api/calendar/connection`.
- `GET /api/calendar/fixed-classes`
  - Response: `{ "classes": [{ "id": "...", "day_of_week": 1, "start_time": "09:00", "end_time": "10:00", "class_name": "Math", "class_type": "lecture" }] }`.
- `POST /api/calendar/fixed-classes/bulk`
  - Request: `{ "classes": [{ "day_of_week": 1, "start_time": "09:00", "end_time": "10:00", "class_name": "Math", "class_type": "lecture" }] }`.
  - Response: `{ "classes": [...] }`.
- OAuth callbacks: `GET /api/calendar/oauth/callback` and `GET /api/calendar/google/callback`.

Canonical orchestration routes:

- `GET /api/orchestration/overview`.
- `POST /api/orchestration/runs`
  - Request: `{ "kind": "assignment_breakdown", "clientKey": "...", "sourceSurface": "mobile", "payload": { "text": "..." } }`.
  - Response: `{ "run": { "id": "...", "kind": "assignment_breakdown", "status": "QUEUED", "attemptCount": 1, "payload": {}, "resultPayload": null, "warningSummary": null, "errorMessage": null } }`.
  - Supported `kind` values: `assignment_breakdown`, `subtask_breakdown`, `schedule_rebuild`, `syllabus_parse`, and `timetable_extract`.
  - Supported statuses: `QUEUED`, `PROCESSING`, `COMPLETED`, `COMPLETED_WITH_WARNINGS`, `FAILED`, `FAILED_TIMEOUT`, and `CANCELLED`.
- `GET /api/orchestration/runs/:id`
  - Response: `{ "run": { "id": "...", "events": [], "chunkResults": [] } }`.
- `POST /api/orchestration/runs/:id/retry`.
- `POST /api/orchestration/runs/:id/cancel`.

Canonical workspace routes:

- `GET /api/workspaces/overview`.
- `POST /api/workspaces`.
- `POST /api/workspaces/join`.
- `GET /api/workspaces/:id/share`.
- `POST /api/workspaces/:id/members`.
- `PATCH /api/workspaces/:id/members/:memberUserId`.
- `POST /api/workspaces/:id/tasks`.

Error response shape:

```json
{
  "error": "Human-readable error label",
  "details": "Optional deeper explanation"
}
```

Client display rule:

1. Show `details` if present.
2. Otherwise show `error`.
3. Otherwise show a client fallback message.

Headers to preserve for diagnostics:

- `x-request-id`.
- `retry-after`.

## 10. Data Model Requirements

Core tables and purpose:

- `users`: app identity, access flags, and account state.
- `user_profiles`: wake/sleep/meal/transit scheduling preferences.
- `primary_tasks`: top-level imported or generated task groups.
- `sub_tasks`: actionable task rows shown in dashboard and schedule.
- `tasks`: direct task-engine task records where still used by AI/write-access flows.
- `ingest_pipeline_runs`: resumable task ingestion state.
- `fixed_classes`: weekly recurring classes.
- `orchestration_runs`: async AI run state.
- `orchestration_events`: orchestration timeline events.
- `orchestration_chunk_results`: chunked AI outputs and retry data.
- `workspaces`: collaboration rooms.
- `workspace_members`: membership, role, and status.
- `workspace_tasks`: task assignments inside workspaces.
- `workspace_activity_events`: collaboration activity.
- `completion_events`: completion history.
- `notification_preferences`: reminder and delivery preferences.
- `reminder_jobs`: scheduled reminders.
- `reminder_deliveries`: delivery status.
- `web_push_subscriptions`: browser push endpoints.
- `calendar_connections`: Google Calendar connection metadata.
- `calendar_calendars`: synced calendar list.
- `calendar_busy_intervals`: external busy intervals.
- `managed_schedule_events`: app-created calendar events.

Data requirements:

- Every user-owned record must either carry `user_id` or be reachable only through a membership/ownership relation.
- Tables with user data must enforce RLS.
- Backend write paths must not trust client-supplied `user_id`.
- Client-generated idempotency keys and run IDs must be ownership-checked before reuse.

Canonical task storage model:

- `tasks` is the direct/manual task table.
  - It is used by direct task creation and current AI `CREATE_TASK` write flows.
  - It carries user-facing fields such as `title`, `description`, `due_date`, `priority_level`, and `status`.
  - `GET /api/tasks` returns these rows for the authenticated user.
- `primary_tasks` is the top-level generated/imported task group table.
  - It represents a course, imported assignment, or generated decomposition container.
  - It is created by generated-task persistence such as `POST /api/tasks/save-run`.
  - It is not the same thing as a direct/manual `tasks` row.
- `sub_tasks` is the actionable generated task-row table.
  - It stores generated or scheduled units of work, estimated duration, priority metadata, completion status, schedule fields, and pipeline links.
  - `GET /api/tasks/rows` returns these rows for dashboard, schedule, reminder, and generated-task flows.
  - Completion, reminder, schedule, workspace, and analytics features should use `sub_tasks` when operating on generated academic work.
- `ingest_pipeline_runs` owns resumable pipeline state.
  - It links generated/imported work to run IDs, logical task IDs, optimizer payloads, schedule rows, retry state, and recovery state.
- Any UI that must display both manual tasks and generated academic work must explicitly merge `GET /api/tasks` with `GET /api/tasks/rows` or use an existing aggregate route that already returns both. Do not change the meaning of either route.

## 11. Mobile Architecture Requirements

- Keep `lib/` feature-first.
- Use `features/<domain>/data` for repositories and models.
- Use `features/<domain>/presentation` for providers and UI state.
- Use `core/` for network, config, errors, Supabase client, auth gate, and shared widgets.
- Use `app/` for app-level theme and shell concerns.
- Widgets must not call HTTP directly; repositories or service classes own API access.
- Use Riverpod providers/controllers for async feature state.
- Keep `StatefulWidget` usage to local form and UI state.
- Parse backend errors through a shared error model.
- Preserve `x-request-id` when available.
- Use `flutter analyze` and targeted `flutter test` after changes.

## 12. UX and Design Requirements

- The mobile app should open into the actual student workflow after auth, not a marketing page.
- Empty states should explain the current state without implying failure.
- Loading states should be specific to the data being loaded.
- Error states should provide a retry path.
- Task, schedule, reminder, and workspace views should support refresh after mutation.
- AI surfaces should make it obvious what was created or changed.
- The interface should remain calm, readable, and mobile-first.
- Dashboard content should prioritize immediate student decisions: what is due, what is next, what is blocked, and what action is available.

## 13. Implementation Milestones

Milestone 1: Foundation

- Verify local environment files.
- Boot Redis, backend, web, AI service, and optimizer service as needed.
- Confirm backend readiness.
- Confirm mobile app can start and initialize Supabase.

Milestone 2: Auth

- Complete sign-in, sign-up, session persistence, auth gate, sign-out, and tokenized backend calls.

Milestone 3: Tasks

- Complete task fetching, task rows, task creation, completion updates, deletion flows, and task empty/error/loading states.

Milestone 4: AI assistant

- Complete mobile AI chat, backend contextual prompt, proactive `ACTION` enforcement, generated task save flow, parser tests, and end-to-end AI task creation.

Milestone 5: Schedule and profile

- Complete profile settings, fixed classes, schedule overview, and schedule persistence.

Milestone 6: Calendar

- Complete calendar status, connect URL, sync, rebuild, and disconnect flows.

Milestone 7: Analytics and reminders

- Complete analytics overview, notification preferences, reminder creation, reminder updates, and dashboard integration.

Milestone 8: Workspaces

- Complete workspace overview, create, join, share, member management, and assignment flows.

Milestone 9: Final hardening

- Run backend tests.
- Run frontend build.
- Run mobile analyze and targeted Flutter tests.
- Verify RLS/cross-account protections.
- Verify end-to-end happy paths on a seeded account and a fresh account.

## 14. Definition of Done

The project is complete when:

- Users can sign up, sign in, sign out, and recover from expired sessions.
- Authenticated mobile requests reach the backend with Supabase bearer tokens.
- Users can create, retrieve, update, complete, and delete their own tasks.
- Users cannot access or mutate another user's data.
- Dashboard, task, schedule, calendar, profile, workspaces, analytics, reminders, and AI views all handle loading, empty, success, and error states.
- AI chat can answer questions using current task context.
- AI planning requests can create tasks proactively through a backend-validated action path.
- Fixed classes and profile schedule settings persist.
- Reminders can be created and updated for owned subtasks.
- Workspaces support create, join, share, membership, and valid task assignment.
- Orchestration runs can be created, polled, retried, and cancelled where appropriate.
- Backend readiness passes.
- Backend tests pass.
- React frontend builds.
- Flutter analyze passes.
- Targeted Flutter tests pass for changed UI/provider logic.
- Known production gaps are either resolved or explicitly documented.

## 15. Verification Plan

Backend:

- Run `npm test` in `student-task-orchestrator/backend`.
- Run `npm run readiness` in `student-task-orchestrator/backend`.
- Confirm `GET /api/health` returns a healthy response.
- Validate protected endpoints reject missing auth.
- Validate cross-account write attempts fail.

Python services:

- Run `python -m pytest -q` in `student-task-orchestrator/ai_service`.
- Run `python -m pytest -q` in `student-task-orchestrator/optimizer-service`.
- If service startup is part of the verification slice, start the AI service with `python -m uvicorn main:app --host 127.0.0.1 --port 8001 --reload`.
- If service startup is part of the verification slice, start the optimizer service with `python -m uvicorn app.main:app --host 127.0.0.1 --port 8002 --reload`.
- Do not expose Python services directly to mobile. Backend-owned routes must remain the integration boundary.

React frontend:

- Run `npm run build` in `student-task-orchestrator/frontend`.
- Smoke test `http://127.0.0.1:5174/signin`.
- Smoke test authenticated app shell behavior.

Flutter mobile:

- Run `flutter pub get` when dependencies change.
- Run `flutter analyze`.
- Run targeted `flutter test`.
- Test Android emulator backend access through `http://10.0.2.2:5000/api`.
- Verify auth, dashboard, tasks, AI chat, schedule, profile, reminders, and workspaces on device/emulator.

AI action path:

- Seed or create a task-bearing account.
- Ask "What do I have to do today?" and verify the answer cites actual stored tasks.
- Ask "i have a math exam on friday help me plan my study session for it tomorrow morning".
- Verify the AI returns a confirmation.
- Verify Supabase contains the created task under the authenticated user's account.
- Verify mobile refresh shows the task.

Seed-account verification contract:

- Use non-production Supabase resources unless production mutation is explicitly approved.
- Seed or manually create at least one fresh blank student account.
- Seed or manually create at least one student account with representative data:
  - profile settings with wake/sleep/meals/transit buffer,
  - direct/manual `tasks` rows,
  - generated `primary_tasks` and `sub_tasks` rows,
  - at least one incomplete subtask and one completed subtask,
  - at least one fixed class,
  - at least one reminder job and delivery,
  - at least one workspace with an active member and assignment,
  - at least one orchestration run with events or chunk results where available.
- Seed or manually create a second student account for cross-account RLS checks.
- The seeded dataset must never require client-side service-role keys.
- Treat seed credentials as secrets; do not commit real passwords or production tokens.

## 16. Known Gaps and Risks

- Production backend API URL is not committed.
- No OpenAPI spec or Postman collection is committed.
- No committed seeded Supabase test account dataset exists.
- No dedicated high-resolution mobile branding export pack is committed.
- Mobile native push notification design is not finalized.
- Google Calendar production OAuth configuration must be confirmed before release.
- Some older local docs mention `localhost:5173`; current verified frontend development URL is `http://127.0.0.1:5174`.
- The repository contains generated logs and emulator artifacts that should not be treated as source-of-truth product docs.
- Existing uncommitted backend changes should be reviewed before any future code modifications or commits.

## 17. Reference Commands

Backend:

```powershell
cd C:\Users\USER\Downloads\student-task-orchestrator\student-task-orchestrator\backend
npm test
npm run readiness
```

Python AI service:

```powershell
cd C:\Users\USER\Downloads\student-task-orchestrator\student-task-orchestrator\ai_service
python -m pytest -q
python -m uvicorn main:app --host 127.0.0.1 --port 8001 --reload
```

Python optimizer service:

```powershell
cd C:\Users\USER\Downloads\student-task-orchestrator\student-task-orchestrator\optimizer-service
python -m pytest -q
python -m uvicorn app.main:app --host 127.0.0.1 --port 8002 --reload
```

React frontend:

```powershell
cd C:\Users\USER\Downloads\student-task-orchestrator\student-task-orchestrator\frontend
npm run dev -- --host 127.0.0.1 --port 5174
npm run build
```

Flutter mobile:

```powershell
cd C:\Users\USER\Downloads\student-task-orchestrator\rakanstudent_mobile
C:\Users\USER\Downloads\flutter_windows_3.29.1-stable\flutter\bin\flutter.bat pub get
C:\Users\USER\Downloads\flutter_windows_3.29.1-stable\flutter\bin\flutter.bat analyze
C:\Users\USER\Downloads\flutter_windows_3.29.1-stable\flutter\bin\flutter.bat test
```

Docker backend from repo root:

```powershell
cd C:\Users\USER\Downloads\student-task-orchestrator
docker compose up --build
```

## 18. Final Product Narrative

In the finished RakanStudent app, a student signs in and immediately sees the shape of their academic day: pending work, scheduled blocks, classes, reminders, and collaboration updates. They can add tasks manually, import them, or ask the AI to help. When they say they have an exam, assignment, or study goal, the AI does not hand the work back to them. It breaks the goal into practical tasks, creates the records, schedules them around fixed classes and personal constraints, and confirms what changed.

The student can trust the system because data is private by default, every client uses the same backend contract, every important mutation is authenticated and scoped, and every failure can be traced. The final platform is not just a task list. It is a student command center that turns academic chaos into an executable plan.
