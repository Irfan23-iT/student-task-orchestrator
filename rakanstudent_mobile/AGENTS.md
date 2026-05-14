# Agent Instructions

## Workflow
- Follow the **Caveman Ultra** methodology: **Plan, Execute, and Test**.
- **Plan**:
  1. Clarify constraints from `../student-task-orchestrator/MOBILE_APP_HANDOFF.md` using `$deep-interview`.
  2. Agree on the plan and architecture impact using `$ralplan`.
- **Execute**:
  1. Implement one feature/domain at a time using `$ralph` for persistent loops or `$team` for parallel work.
  2. Follow the sequence: `auth` -> `tasks` -> `schedule` -> `workspaces` -> `analytics/calendar`.
- **Test**:
  1. Verify with `flutter analyze` and targeted tests before moving on.
  2. Ensure `flutter pub get` is run if dependencies changed.

## Package Manager
- Use Flutter tooling: `flutter pub get`, `flutter analyze`, `flutter test`
- Flutter SDK path in this workspace:
```powershell
C:\Users\USER\Downloads\flutter_windows_3.29.1-stable\flutter\bin\flutter.bat
```

## File-Scoped Commands
| Task | Command |
|------|---------|
| Format | `dart format lib/path.dart test/path_test.dart` |
| Analyze | `flutter analyze` |
| Test file | `flutter test test/widget_test.dart` |
| Add package | `flutter pub add package_name` |

## Architecture
- Keep `lib/` feature-first: `features/<domain>/data`, `features/<domain>/presentation`, shared code in `app/` and `core/`
- Put API access in repositories; widgets must not call HTTP directly
- Put app-wide config, network, errors, and shared widgets in `lib/core/`
- Use Riverpod providers/controllers for async feature state; keep `StatefulWidget` for local form/UI state only

## Backend Rules
- Treat `../student-task-orchestrator/MOBILE_APP_HANDOFF.md` as the backend contract
- Mobile app talks only to the Node backend `/api/...`, not Python services directly
- Authenticate with Supabase on-device, then send `Authorization: Bearer <access_token>` to protected backend routes
- Preserve and surface `x-request-id` on backend failures when available
- Parse backend errors as `{ "error", "details" }`; show `details` first when present

## Environment
- Required `.env` keys:
  - `MOBILE_API_BASE_URL`
  - `MOBILE_SUPABASE_URL`
  - `MOBILE_SUPABASE_ANON_KEY`
- Never commit `.env`; keep `.env` and `*.env` ignored

## Verification
- Minimum before completion:
  - `flutter pub get` if dependencies changed
  - `flutter analyze`
  - targeted `flutter test` when UI or provider logic changes

## Commit Attribution
- AI commits MUST include:
```text
Co-Authored-By: OpenAI Codex <noreply@openai.com>
```
