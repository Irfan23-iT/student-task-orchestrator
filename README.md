# RakanStudent Capstone

RakanStudent is a multi-client academic productivity platform composed of:

- Flutter mobile client: `rakanstudent_mobile/`
- React web client: `student-task-orchestrator/frontend/`
- Node.js API gateway: `student-task-orchestrator/backend/`
- Python AI service: `student-task-orchestrator/ai_service/`
- Supabase database and auth

See [ARCHITECTURE.md](C:/Users/USER/Downloads/student-task-orchestrator/ARCHITECTURE.md) for the system design and security model.

## Quick Start

### 1. Run the backend with Docker Compose

From the repository root:

```powershell
docker compose up --build
```

This starts the Node.js backend container defined in:

- [docker-compose.yml](C:/Users/USER/Downloads/student-task-orchestrator/docker-compose.yml)
- [backend/Dockerfile](C:/Users/USER/Downloads/student-task-orchestrator/student-task-orchestrator/backend/Dockerfile)

The compose stack reads backend configuration from:

- `student-task-orchestrator/backend/.env`

Default exposed backend port:

- `5000`

### 2. Run the React Web Client

```powershell
cd student-task-orchestrator\frontend
npm install
npm run dev
```

Production build:

```powershell
npm run build
```

### 3. Run the Flutter Mobile Client

```powershell
cd rakanstudent_mobile
flutter pub get
flutter run
```

Release APK:

```powershell
flutter build apk --release
```

### 4. Run the Python AI Service

```powershell
cd student-task-orchestrator\ai_service
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
```

## Environment Notes

Backend env example lives at:

- `student-task-orchestrator/backend/.env.example`

Frontend local envs live at:

- `student-task-orchestrator/frontend/.env`
- `student-task-orchestrator/frontend/.env.local`

Flutter mobile env lives at:

- `rakanstudent_mobile/.env`

## Project Layout

```text
.
├── docker-compose.yml
├── ARCHITECTURE.md
├── README.md
├── rakanstudent_mobile/
└── student-task-orchestrator/
    ├── ai_service/
    ├── backend/
    └── frontend/
```
