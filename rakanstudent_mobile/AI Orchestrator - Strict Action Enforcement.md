# PRD: AI Orchestrator - Strict Action Enforcement

## 1. Context
The application has successfully integrated an AI Orchestrator with "Write Access" (Path A) to the Supabase database. The architecture correctly parses `ACTION: {"type": "CREATE_TASK"...}` blocks and executes them. However, current real-world testing reveals that the LLM is behaving passively. When a user states an upcoming event (e.g., "I have a math exam on Friday, help me plan"), the AI provides conversational advice and instructs the user to manually add the task, rather than proactively utilizing its `CREATE_TASK` capability.

## 2. Objective
To refine and enforce the System Prompt within the backend AI Controller. The goal is to transform the AI from a "passive advisor" into a "proactive executive assistant." The AI must autonomously execute database actions whenever a user implies a scheduling need, without pushing the manual labor back onto the user.

## 3. Requirements

### 3.1 Backend (Node.js) Prompt Engineering
*   **Target File:** `backend/controllers/aiController.js`
*   **System Prompt Overhaul:** Update the LLM instructions with strict, uncompromising behavioral directives:
    *   **Role Definition:** "You are an autonomous executive assistant with direct database write access. You do not give the user instructions to do things you can do yourself."
    *   **Action Mandate:** "CRITICAL: If the user asks to plan, schedule, remind, or states they have an upcoming event (like an exam or meeting), YOU MUST automatically generate the `ACTION: {"type": "CREATE_TASK", "data": {...}}` JSON block."
    *   **Forbidden Phrases:** Explicitly forbid the AI from using phrases like "Add this to your list," "To get started, create a task," or "Make sure to schedule."
    *   **Contextual Proactivity:** If the user gives a broad goal ("Plan my study session"), the AI must break it down and use the `ACTION` block to create the specific task(s) for them, then confirm it in natural language.

### 3.2 Testing & Validation
*   **Regex/Parser Verification:** Ensure the backend parsing logic correctly handles the AI outputting *both* the action block and a natural language confirmation in the same response.

## 4. Definition of Done (DoD)
- [ ] `aiController.js` system prompt is updated with strict action directives.
- [ ] Backend tests continue to pass.
- [ ] **End-to-End Test Passed:** The user inputs the exact phrase: *"i have a math exam on friday help me plan my study session for it tomorrow morning"*. 
- [ ] **Validation:** The AI responds by confirming it has scheduled the session, and the Supabase `tasks` table successfully shows a new task created for tomorrow morning, without the AI asking the user to manually create it.