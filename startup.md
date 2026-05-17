# Startup Guide

This guide starts the local backend server and the Flutter mobile app.

Run each long-running command in its own PowerShell terminal.

## 1. Prerequisites

Install these first:

- Node.js 20+
- Flutter SDK with Android Studio or Xcode configured
- Docker Desktop, or another local Redis installation
- Supabase project URL and anon key
- Supabase service role key for the backend

Check Flutter setup:

```powershell
flutter doctor
```

## 2. Configure the Backend Environment

Create or update:

```text
C:\Users\USER\Downloads\student-task-orchestrator\student-task-orchestrator\backend\.env
```

Minimum local values:

```env
PORT=5000
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_supabase_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_supabase_service_role_key
GEMINI_API_KEY=your_gemini_api_key
REDIS_URL=redis://127.0.0.1:6379
FRONTEND_BASE_URL=http://127.0.0.1:5174
APP_TIMEZONE=UTC
```

## 3. Configure the Mobile Environment

Create or update:

```text
C:\Users\USER\Downloads\student-task-orchestrator\rakanstudent_mobile\.env
```

For an Android emulator:

```env
MOBILE_API_BASE_URL=http://10.0.2.2:5000/api
MOBILE_SUPABASE_URL=your_supabase_url
MOBILE_SUPABASE_ANON_KEY=your_supabase_anon_key
MOBILE_ENV=local
```

For an iOS simulator, use:

```env
MOBILE_API_BASE_URL=http://127.0.0.1:5000/api
```

For a physical phone, use your computer's LAN IP address:

```env
MOBILE_API_BASE_URL=http://YOUR_COMPUTER_LAN_IP:5000/api
```

Example:

```env
MOBILE_API_BASE_URL=http://192.168.1.25:5000/api
```

## 4. Start Redis

If the Redis container does not exist yet:

```powershell
docker run -d --name sto-redis -p 6379:6379 redis:7-alpine
```

If the container already exists:

```powershell
docker start sto-redis
```

## 5. Start the Backend Server

Open a new PowerShell terminal:

```powershell
cd C:\Users\USER\Downloads\student-task-orchestrator\student-task-orchestrator\backend
npm install
npm run dev
```

The backend should run at:

```text
http://127.0.0.1:5000/api
```

Verify the backend health from another terminal:

```powershell
Invoke-WebRequest http://127.0.0.1:5000/api/health
```

For the full readiness report:

```powershell
cd C:\Users\USER\Downloads\student-task-orchestrator\student-task-orchestrator\backend
npm run readiness
```

## 6. Start the Flutter Mobile App

Open a new PowerShell terminal:

```powershell
cd C:\Users\USER\Downloads\student-task-orchestrator\rakanstudent_mobile
flutter pub get
flutter run
```

If multiple devices are connected, list them:

```powershell
flutter devices
```

Then run on a specific device:

```powershell
flutter run -d DEVICE_ID
```

## 7. Optional Supporting Services

The mobile app can start with only Redis and the Node backend, but some AI and scheduling workflows may expect the Python services.

### AI Service

```powershell
cd C:\Users\USER\Downloads\student-task-orchestrator\student-task-orchestrator\ai_service
.\venv\Scripts\Activate.ps1
python -m uvicorn main:app --host 127.0.0.1 --port 8001 --reload
```

### Optimizer Service

```powershell
cd C:\Users\USER\Downloads\student-task-orchestrator\student-task-orchestrator\optimizer-service
.\venv\Scripts\Activate.ps1
python -m uvicorn app.main:app --host 127.0.0.1 --port 8002 --reload
```

## 8. Common Problems

- If the Android emulator cannot reach the server, confirm `MOBILE_API_BASE_URL` is `http://10.0.2.2:5000/api`.
- If a physical phone cannot reach the server, make sure the phone and computer are on the same Wi-Fi network and use the computer's LAN IP.
- If backend readiness fails on Redis, start the `sto-redis` container again.
- If the mobile app throws a missing env error, confirm `rakanstudent_mobile\.env` exists and contains Supabase values.
- If auth or API calls return `401`, check that the mobile anon key and backend Supabase keys are from the same Supabase project.
