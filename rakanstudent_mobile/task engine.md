# PRD: Core Task Engine

## 1. Context
The Student Task Orchestrator has successfully established a secure, request-scoped authentication bridge between the Flutter mobile application, the Node.js backend, and the Supabase database. With the payload normalization and Redis-fallback architecture in place, the application requires its primary business logic layer: **The Task Engine**. 

Currently, the application can authenticate users and manage profiles/settings, but it lacks the foundation to store, retrieve, and manage actionable items. This module will establish the foundational data layer and API routing required for users to manage their workload, which serves as the strict prerequisite before integrating the AI Agent (`AGENTS.md`) orchestration layer.

## 2. Objective
To design and implement a secure, end-to-end task management pipeline that allows authenticated users to create and retrieve tasks. This engine must strictly adhere to the established payload normalization patterns and enforce Row Level Security (RLS) to ensure absolute data privacy between users.

## 3. Requirements

### 3.1 Database (Supabase)
*   **Schema:** Create a new `tasks` table with the following schema:
    *   `id`: UUID (Primary Key, default: `uuid_generate_v4()`)
    *   `user_id`: UUID (Foreign Key linking to `auth.users`, Not Null)
    *   `title`: Text (Not Null)
    *   `description`: Text (Nullable)
    *   `due_date`: Timestamp with Time Zone (Nullable)
    *   `priority_level`: Enum/Text (e.g., 'Low', 'Medium', 'High')
    *   `status`: Enum/Text (e.g., 'Pending', 'In Progress', 'Completed', default: 'Pending')
    *   `created_at`: Timestamp (default: `now()`)
*   **Security:** Enable Row Level Security (RLS) on the `tasks` table.
*   **Policies:** Create strict policies ensuring authenticated users can only `SELECT`, `INSERT`, `UPDATE`, and `DELETE` rows where `tasks.user_id = auth.uid()`.

### 3.2 Backend (Node.js)
*   **Controller:** Implement `backend/controllers/taskController.js`.
*   **Routes:** 
    *   `GET /api/tasks`: Retrieve all tasks for the authenticated user.
    *   `POST /api/tasks`: Create a new task.
*   **Authentication:** Routes must utilize the existing `req.supabase` request-scoped client to automatically inherit the user's Bearer token context.
*   **Error Handling:** Implement explicit error logging (e.g., `console.error("Task Creation Failed:", error.message, "Payload:", req.body)`) and return standardized HTTP status codes (200, 201, 400, 401, 500) to the client.

### 3.3 Frontend (Flutter)
*   **Service Layer:** Update `lib/services/api_service.dart`.
*   **Methods:** Implement `getTasks()` and `createTask(Map<String, dynamic> taskData)`.
*   **Headers:** Ensure both methods utilize the established `_getHeaders()` method to pass the active Supabase session access token.

## 4. Definition of Done (DoD)
The module is considered complete when it passes the "Plan, Execute, and Test" workflow criteria:

- [ ] **Database Executed:** A Supabase migration file exists for the `tasks` table and has been successfully applied to the database.
- [ ] **RLS Verified:** A direct database query attempting to access another user's task returns `[]` or fails.
- [ ] **Backend Executed:** `taskController.js` is implemented, routes are registered in `server.js`, and the server starts without syntax errors.
- [ ] **Frontend Executed:** `api_service.dart` is updated and compiles successfully (`flutter analyze` passes).
- [ ] **End-to-End Test Passed:** A dummy task created via the Flutter mobile UI successfully traverses the Node.js backend and appears in the Supabase Table Editor attached to the correct `user_id`.
- [ ] **Error Handling Verified:** Sending a malformed POST payload returns a descriptive 400-level error to the client rather than silently failing or crashing the server.