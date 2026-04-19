# RakanStudent Architecture

## System Overview

RakanStudent is a multi-client academic orchestration platform with shared authentication and a service-oriented backend:

- Flutter Mobile Client
  - Native student experience for dashboard, schedule, tasks, analytics, and workspace collaboration.
  - Uses Supabase Auth on-device, then calls the Node.js API with a bearer JWT.
- React Web Client
  - Browser dashboard for context ingest, task orchestration, analytics, workspace features, and settings.
  - Uses Supabase Auth in-browser and sends the same JWT to the Node.js API.
- Node.js API Gateway
  - Primary backend edge service for authenticated REST APIs.
  - Owns route authorization, request validation, task/workspace/analytics persistence, orchestration run lifecycle, and integration endpoints.
- Python AI Service
  - Specialized AI execution layer for assignment breakdown, syllabus parsing, timetable extraction, and schedule generation.
  - Uses strict JSON-oriented prompting plus output normalization/fallback handling before results are persisted.
- Supabase Database
  - System of record for users, tasks, workspaces, analytics, orchestration runs, calendar data, and related collaboration tables.
  - Provides auth primitives plus database-level Row Level Security protections.

## High-Level Flow

1. User authenticates with Supabase from Flutter or React.
2. Client receives a session JWT.
3. Client sends `Authorization: Bearer <jwt>` to the Node.js API.
4. Node.js API verifies JWT claims, resolves account access state, and authorizes the request.
5. For standard CRUD flows, Node.js reads/writes Supabase directly.
6. For AI flows, Node.js creates orchestration records and the Python AI service produces structured outputs.
7. Normalized outputs are written back to Supabase and surfaced to both clients.

## Authentication Flow (JWT)

- Supabase issues the access token after sign-in.
- Flutter Mobile Client and React Web Client both store/use that token locally.
- The Node.js API enforces authentication through JWT middleware mounted at `/api`.
- Middleware behavior:
  - Extracts bearer token.
  - Verifies claims.
  - Rejects missing/invalid tokens with `401`.
  - Applies account-state checks such as disabled, banned, or revoked sessions.
- Protected endpoints only execute after `req.user` is populated with:
  - authenticated user id
  - authenticated user email
  - verified claims payload

## Database Security

### RLS

Supabase remains the authoritative security boundary at the data layer through Row Level Security for user-owned and collaboration-scoped tables. This ensures records are limited to authorized principals even if an upstream service drifts.

### Recent IDOR / Cross-Account Hardening

Recent production audit patches strengthened defense in depth on top of RLS:

- Task mutation paths now re-apply `user_id` filters on update and parent-status synchronization.
- Reminder creation now verifies the referenced subtask belongs to the authenticated user.
- Push subscription upsert now rejects endpoint reuse across different users.
- Workspace overview now derives from active memberships only.
- Workspace task assignment now requires the assignee to already be an active workspace member.
- Pipeline state upsert now verifies ownership before allowing writes to caller-supplied run ids.

These changes reduce IDOR and cross-account write risk even when services are using elevated backend credentials.

## Deployment Topology

- Clients:
  - Flutter app runs on device/emulator.
  - React app runs in browser or static hosting.
- Backend:
  - Node.js API can run locally or in a container.
  - Python AI service runs separately and can be deployed independently.
- Data:
  - Supabase hosts auth and persistence.

## Operational Notes

- The provided `docker-compose.yml` currently orchestrates the Node.js backend service only.
- Web and mobile clients still run separately in local development.
- The Python AI service is documented here but is not included in the current compose stack.
