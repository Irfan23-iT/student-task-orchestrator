# PRD: AI Orchestrator Integration

## 1. Context
The Core Task Engine is live and secured with RLS. The application can now store and retrieve authenticated user tasks. The final foundational phase is integrating the "Brain"—the AI Orchestrator (`AGENTS.md`). This module will connect a Large Language Model (LLM) to the backend, giving it the ability to read the user's tasks, suggest schedule optimizations, and eventually create tasks via natural language.

## 2. Objective
To build a secure, context-aware AI chat interface within the Flutter app that communicates with a new backend AI controller. The backend controller will securely fetch the user's task data, inject it into the LLM's system prompt, and return the AI's intelligent response to the mobile client.

## 3. Requirements

### 3.1 Backend (Node.js)
*   **Controller:** Implement `backend/controllers/aiController.js`.
*   **Route:** `POST /api/ai/chat` 
*   **Authentication:** Must use the existing `req.supabase` request-scoped client.
*   **Logic Pipeline:**
    1. Receive the user's natural language prompt from the Flutter app.
    2. Query the `tasks` table via `req.supabase` to get the user's current active tasks.
    3. Construct a System Prompt that includes the user's current tasks as JSON context. (e.g., "You are an AI assistant. The user has the following tasks due today: [Task Data]").
    4. Send the prompt + context to the configured LLM API (e.g., Google Gemini or OpenAI).
    5. Return the LLM's text response to the client.

### 3.2 Frontend (Flutter)
*   **UI:** Create `lib/views/ai_chat_view.dart`. This should be accessible via a Floating Action Button (FAB) or a persistent bottom navigation tab.
*   **Service Layer:** Update `lib/services/api_service.dart` with `sendChatMessage(String message)`.
*   **State:** Maintain a simple local chat history (User vs. AI messages) within the view session.

## 4. Definition of Done (DoD)
- [ ] Backend route `POST /api/ai/chat` is implemented and securely scoped to the authenticated user.
- [ ] The backend successfully queries the user's tasks and passes them as context to the LLM.
- [ ] The Flutter app features a functional chat UI.
- [ ] **End-to-End Test:** The user types "What do I have to do today?" in the Flutter app, and the AI correctly responds by listing a task that was previously created in the Task Engine.