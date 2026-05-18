# Rakan Student

**Your AI-powered study command center.** Rakan Student is a gamified productivity suite for university students who need one place to capture tasks, plan classes, protect focus time, and stay motivated. It combines a polished Flutter mobile app, a Node.js orchestration backend, Supabase/PostgreSQL persistence, and local-first reward mechanics into a companion that feels closer to a study partner than a plain task list.

The current feature-freeze build is centered on the Flutter mobile experience: voice-to-task capture, a reactive dashboard, calendar-aware planning, a local Gacha reward loop, and an immersive Deep Work Room designed for distraction-free study sessions.

## The Flex

### Voice-to-Task AI Orchestration

Speak a messy reminder, and Rakan Student turns it into structured task data. The mobile app captures speech locally with `speech_to_text`, sends the transcription to the Node.js AI route, and refreshes the task list immediately when the orchestrator creates the new reminder.

### Gacha-Based Gamification

Completed tasks feed a lightweight local economy. Every three completed tasks earns a token, and tokens can be spent in the Mystery Box to unlock collectible loot. The Gacha controller stays local by design, making the reward loop fast, private, and independent from backend availability.

### Immersive Deep Work Room

The Focus experience has graduated from a basic timer into a full-screen Deep Work Room. Students can choose 15, 25, 45, or 60 minute blocks, tune a custom duration with a slider, and enter a lockdown-style session that uses `wakelock_plus` plus immersive system UI mode to keep the screen awake and the interface calm.

### Reactive Dashboard and Calendar Sync

The dashboard keeps high-signal study context in sync: pending tasks, active reminders, upcoming classes, and calendar markers. Recent fixes ensure the Tasks Pending and Next Class Bento cards listen to the correct state, while the calendar defensively deduplicates overlapping task streams before rendering.

## Tech Stack

### Mobile

- Flutter and Dart
- Riverpod and `ValueNotifier` state surfaces
- Supabase Flutter for auth and data access
- `http` for backend API calls
- `speech_to_text` for voice capture
- `wakelock_plus` for Deep Work Room hardware integration
- `table_calendar`, `intl`, local notifications, secure storage, and image picking

### Backend

- Node.js with Express 5
- Supabase JavaScript client
- PostgreSQL via Supabase
- Redis integration for backend readiness and supporting workflows
- Google Gemini SDK packages for AI orchestration routes

### Data and Architecture

- Supabase Auth protects user identity.
- Supabase/PostgreSQL stores profiles, tasks, schedules, reminders, analytics, and workspace data.
- The Flutter app talks to Supabase directly for selected client-owned flows and to the Node.js API for protected orchestration workflows.
- The dashboard consumes backend analytics plus schedule data, then maps them into UI-specific summary DTOs.
- Gacha tokens and loot are intentionally local-only for this feature-freeze release.

> Note: earlier planning referenced `just_audio` for focus soundscapes. The current feature-freeze implementation intentionally dropped the audio requirement, so `just_audio` is not part of the active mobile dependency set unless audio ambience is reintroduced later.

## Repository Layout

```text
.
|-- rakanstudent_mobile/              # Flutter mobile app
|   |-- lib/features/                 # Auth, dashboard, tasks, focus, gacha, profile, schedule
|   |-- test/                         # Widget and DTO regression tests
|   |-- android/                      # Android native permissions and runner
|   `-- ios/                          # iOS native permissions and runner
|-- student-task-orchestrator/
|   |-- backend/                      # Node.js Express API
|   |-- frontend/                     # Web dashboard surface
|   |-- ai_service/                   # Python AI service workspace
|   `-- optimizer-service/            # Python optimizer service workspace
|-- ARCHITECTURE.md
|-- IMPLEMENTATION_STATUS.md
`-- README.md
```

## Getting Started

### 1. Clone the Repository

```bash
git clone <your-repository-url>
cd student-task-orchestrator
```

### 2. Configure the Flutter App

```bash
cd rakanstudent_mobile
flutter pub get
```

Create a mobile environment file from the example:

```bash
cp .env.example .env
```

Fill in the required values for your Supabase project and backend URL. For Android emulator testing, the backend is commonly reached through `http://10.0.2.2:5000/api`.

### 3. Run the Mobile App

```bash
flutter run
```

For native voice capture, make sure the platform permissions are present:

- Android: `RECORD_AUDIO`, `INTERNET`, and Bluetooth permission entries in `android/app/src/main/AndroidManifest.xml`.
- iOS: microphone and speech recognition usage descriptions in `ios/Runner/Info.plist`.

### 4. Start the Backend API

```bash
cd ../student-task-orchestrator/backend
npm install
npm run dev
```

The backend runs on port `5000` by default and exposes API routes for auth-adjacent workflows, AI chat/actions, tasks, schedule, analytics, settings, workspaces, and health readiness.

### 5. Optional Web Dashboard

```bash
cd ../frontend
npm install
npm run build
```

## Testing Pipeline

The mobile feature-freeze baseline has a fully green Flutter test suite:

```text
35/35 widget and DTO tests passing
```

Run the checks from the Flutter app directory:

```bash
cd rakanstudent_mobile
flutter analyze
flutter test
```

Current coverage includes:

- Auth shell and validation flows
- Reactive Dashboard Next Class updates
- Tasks Pending count behavior
- Calendar task deduplication
- Deep Work Room setup controls
- Local Gacha Mystery Box rendering
- Tasks, profile, schedule, timer, AI chat, and navigation widget smoke tests

## Feature Freeze Status

Rakan Student is currently stabilized around the mobile experience. The priority is preserving behavior, keeping the UI reactive, and maintaining the green test suite while future work is staged behind clear implementation boundaries.

Planned extension points include richer AI orchestration, optional focus soundscapes, deeper analytics, and expanded collaborative workspace workflows.
