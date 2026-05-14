# PRD: Standalone Pivot - "Snap & Schedule" Vision Orchestrator

## 1. Context & Objective
The application is pivoting to a standalone, mobile-native task orchestrator. We are replacing the web-dependent PDF upload flow with a native mobile camera flow. 
**Objective:** Integrate a Vision AI pipeline so a user can take a picture of a syllabus, whiteboard, or handwritten notes, and the AI will extract the deadlines and automatically schedule them on the Flutter calendar using our existing orchestration engine.

## 2. Infrastructure & Constraints (STRICT)
- **Verified Database:** All operations must target the new private Supabase instance at `https://jklxmrmoeshtyaxbvcnn.supabase.co`.
- **Zero Schema Mutations:** Do NOT alter existing table structures. The data must fit the `primary_tasks` and `sub_tasks` relational model.
- **Cost Efficiency:** No Supabase Storage buckets. Images must be compressed, converted to Base64 in Flutter, and processed in-memory in the backend.
- **AI Model:** Update the AI Controller to use a multimodal model (Gemini 1.5 Flash via `@google/genai`) capable of parsing Base64 image payloads.

## 3. Execution Steps

### Phase 1: Environment & Safety Check
1. Checkout a new Git branch: `feature/standalone-pivot-vision`.
2. Confirm the `.env` reflects the `jklxmrmoeshtyaxbvcnn` project URL and keys.
3. Verify the `tasks`, `primary_tasks`, and `sub_tasks` tables exist in the new schema.

### Phase 2: Backend AI Controller (`backend/controllers/aiController.js`)
1. **New Route:** Implement `POST /api/ai/vision-parse`.
2. **Payload Parsing:** Accept JSON containing `{ "image_base64": "<string>" }`.
3. **Multimodal Prompting:** > *"You are an academic coordinator. Analyze this image for assignments, exams, or deadlines. For every item found, output a raw JSON action block. Differentiate between Single Tasks and Complex Projects. For projects, generate 3-5 logical milestones as sub-tasks. FORMAT: ACTION: {"type": "CREATE_TASK", "data": {...}} or ACTION: {"type": "CREATE_PRIMARY_TASK", "data": {...}}."*
4. **Execution:** Pass the AI output through the existing `actionParser` to write to the new Supabase instance.

### Phase 3: Mobile Frontend (`rakanstudent_mobile`)
1. **Dependencies:** Add `image_picker` to `pubspec.yaml`.
2. **UI Integration:** Add a Camera FAB (Floating Action Button) to the `CalendarView`.
3. **Camera Logic:** - Capture image -> Compress (< 1MB) -> Convert to Base64.
4. **API Integration:**
   - Display a "Scanning & Orchestrating..." loading modal.
   - POST Base64 to `/api/ai/vision-parse`.
   - On `200 OK`: Dismiss loader, trigger state refresh to show new calendar dots.

## 4. Definition of Done (DoD)
- [ ] Backend successfully handles Base64 images and orchestrates database inserts.
- [ ] AI correctly populates `primary_tasks` and `sub_tasks` from a photo.
- [ ] Flutter app captures and sends images without memory crashes.
- [ ] Calendar UI updates dynamically to show new tasks in the new Supabase project.

## 5. Codex Instructions
Initialize by verifying the new Supabase Project ID is active. Implement the Vision-to-Database pipeline. Ensure all AI-generated sub-tasks maintain correct foreign-key relationships with their parent primary tasks.