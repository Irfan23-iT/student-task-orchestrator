# Rakan Student

Rakan Student is an AI-native academic task ecosystem built to help students turn scattered coursework, deadlines, revision plans, and focus sessions into an organized daily execution system. It combines a Flutter-first mobile experience, Supabase-backed identity and persistence, a Node.js orchestration backend, Redis-backed run handling, and Gemini-powered AI workflows into one cohesive student productivity platform.

The product is designed around a simple principle: students should be able to capture academic intent in the way it naturally appears, whether that is a typed task, an AI chat request, a photographed syllabus, or a focused study session, and have the system translate that intent into structured, actionable work.

## Product Vision

Rakan Student acts as a personal academic operating system:

- Capture tasks, deadlines, classes, and reminders from mobile-first flows.
- Convert unstructured academic inputs into structured task and schedule records.
- Support deep focus through an immersive Deep Work Room.
- Reinforce healthy completion loops with a lightweight Gacha token economy.
- Keep durable academic data in Supabase while allowing fast client-side interaction state where appropriate.

## Core Architecture

The system is composed of four primary layers:

- **Flutter Mobile Client**: The main student-facing app for authentication, dashboards, task management, calendar scheduling, camera scanning, Deep Work, and Gacha.
- **Node.js API Gateway**: The protected backend edge for authenticated REST APIs, task persistence, orchestration lifecycle, analytics, settings, and AI action execution.
- **AI Orchestration Layer**: Gemini-backed workflows that parse academic intent, normalize output, and execute structured actions.
- **Supabase + Redis Infrastructure**: Supabase provides Auth, PostgreSQL persistence, and RLS-protected data ownership; Redis Streams supports bounded orchestration run coordination.

## Engineering Highlights

### Custom Run-Kind Router and State Machine

Rakan Student includes a custom run-kind routing model for orchestration workflows. The backend treats different academic workflows as distinct run kinds, allowing the system to route, persist, poll, retry, and reconcile AI-backed work without collapsing every operation into a generic request-response call.

The architecture uses:

- **Redis Streams** for event-style run progression, queue-friendly orchestration, and bounded asynchronous handling.
- **Supabase** as the durable source of truth for user-owned tasks, orchestration runs, calendar data, analytics, and collaboration state.
- **State-machine style lifecycle handling** for run creation, polling, retry/cancel behavior, and persistence of normalized AI output.

This gives the product a scalable orchestration spine instead of a fragile single-shot AI endpoint.

### Camera Scan and Schedule Pipeline

The mobile app supports a native "Snap and Schedule" workflow for academic materials such as syllabi, whiteboards, worksheets, and handwritten notes.

The pipeline is intentionally cost-efficient and mobile-native:

- Flutter captures an image through the device camera.
- The image is compressed and converted to **Base64** client-side.
- The backend receives the in-memory payload without requiring Supabase Storage buckets.
- Gemini Vision parses the image for assignments, exams, milestones, and deadlines.
- The parsed output is normalized into task actions and persisted through the existing Supabase-backed task model.

This turns visual academic clutter into structured calendar and task data without forcing students through a web upload flow.

### Deep Work Room

Rakan Student includes an immersive Deep Work Room for focused study sessions. The Flutter implementation uses `wakelock_plus` so the device can remain awake during intentional focus periods, reducing friction during revision, writing, or timed study blocks.

The Deep Work Room is designed as a dedicated study environment rather than a basic timer. It supports sustained attention, clear entry and exit states, and a more deliberate focus-mode experience inside the mobile app.

### Client-Side Gacha Token Economy

The app includes a client-side Gacha token economy to make academic completion feel more rewarding without coupling motivation mechanics to backend availability.

The current feature-freeze implementation keeps Gacha state local through Riverpod:

- Task completions increment local progress.
- Every third completion awards a spendable Gacha token.
- Pulling Gacha consumes one token and rolls against a weighted local loot pool.
- The reward loop stays fast, private, and resilient even when backend services are unavailable.

This creates a lightweight gamification layer that encourages consistency while keeping durable academic records separate from local motivational state.

## Mobile Feature Set

- Supabase email/password authentication.
- Dashboard summary for active academic work.
- Task creation, filtering, completion, and schedule-linked views.
- Calendar and fixed-class workflows.
- Camera-based syllabus and deadline scanning.
- AI orchestration entry points for task planning.
- Deep Work Room powered by `wakelock_plus`.
- Gacha rewards driven by local Riverpod state.

## Backend Feature Set

- Authenticated API routes using Supabase bearer tokens.
- Request-scoped Supabase access for user-owned data.
- Task, subtask, analytics, notification, calendar, workspace, and orchestration APIs.
- AI chat and action parsing workflows.
- Readiness diagnostics for Redis and Supabase dependencies.
- Run lifecycle support for asynchronous orchestration patterns.

## Technology Stack

- **Mobile**: Flutter, Dart, Riverpod, Supabase Flutter, `image_picker`, `wakelock_plus`, `table_calendar`.
- **Backend**: Node.js, Express-style API modules, Supabase client integrations.
- **AI**: Gemini Vision and structured action parsing for academic task generation.
- **Data**: Supabase Auth, Supabase PostgreSQL, Row Level Security.
- **Orchestration**: Redis Streams and Supabase-backed run state.
- **Testing**: Flutter widget/unit tests plus backend Node test coverage.

## Verification Status

The Flutter mobile test suite is stabilized and passing with bounded pumps across the current feature surface. The project currently tracks 35 passing Flutter tests covering core UI entry points, focus flows, Gacha behavior, task behavior, and app-level widget stability.

## Repository Layout

```text
.
|-- rakanstudent_mobile/          # Flutter mobile application
|-- student-task-orchestrator/    # Backend, frontend, services, and migrations
|-- scripts/                      # Local setup and helper scripts
|-- ARCHITECTURE.md               # System architecture notes
|-- FYP_SYSTEM_ARCHITECTURE.md    # Full academic system architecture write-up
|-- TASK_DOCUMENT.md              # Canonical product and implementation task document
```

## Summary

Rakan Student is more than a task list. It is a purpose-built academic execution system that combines AI-native capture, durable task orchestration, mobile-first scheduling, immersive focus tooling, and gamified motivation into a single student-centered ecosystem.
