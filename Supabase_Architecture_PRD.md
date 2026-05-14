# PRD: Supabase Schema Expansion & Feature Normalization

## 1. Context & Objective
The "Snap & Schedule" mobile pivot is successful, but the current Supabase schema (`tasks`, `primary_tasks`, `sub_tasks`) is too barebones to support upcoming advanced features (filtering, categorization, dynamic statuses, and notifications). 

**Objective:** Expand the database architecture using strict relational normalization. Do NOT create "a table per task type." Instead, implement metadata columns and relational mapping tables to support infinite future task functions without fracturing the codebase.

---

## 2. Architectural Blueprint (Supabase SQL)
Codex must generate and execute the SQL to safely `ALTER` the existing tables and create the necessary supportive tables in the Supabase project.

### Phase 1: The Taxonomy Tables
Create new tables to handle the "types" and "groupings" of tasks.

* **`categories` Table:**
  * `id` (UUID, Primary Key)
  * `user_id` (UUID, Foreign Key to `auth.users`)
  * `name` (String, e.g., "Academic", "Personal", "Motorsport")
  * `color_hex` (String, for Flutter UI rendering)
  * *RLS:* Users can only manage their own categories.

* **`tags` Table:**
  * `id` (UUID, Primary Key)
  * `user_id` (UUID, Foreign Key to `auth.users`)
  * `name` (String, e.g., "Deep Work", "Urgent")
  * *RLS:* Users can only manage their own tags.

### Phase 2: Upgrading Core Tables (Zero Data Loss)
Modify the existing `tasks` and `primary_tasks` tables to support advanced app functions.

* **Add `status` column:** (String/Enum: `pending`, `in_progress`, `completed`, `archived`). Default to `pending`.
* **Add `task_type` column:** (String: `exam`, `assignment`, `event`, `reminder`). Default to `general`.
* **Add `category_id` column:** (UUID, Nullable, Foreign Key to `categories.id`).
* **Add `notes` column:** (Text, Nullable) for rich-text descriptions.

### Phase 3: The Many-to-Many Mappers
To allow tasks to have multiple tags without breaking normalization.

* **`task_tags_map` Table:**
  * `task_id` (UUID, Foreign Key to `tasks.id` OR `primary_tasks.id`)
  * `tag_id` (UUID, Foreign Key to `tags.id`)
  * *RLS:* Users can only map tags to tasks they own.

---

## 3. Execution Steps for Codex

1. **Draft Migration:** Write the raw Supabase PostgreSQL script to execute Phase 1, Phase 2, and Phase 3 safely. Ensure `ALTER TABLE` statements provide default values where necessary to prevent breaking existing rows.
2. **RLS Enforcement:** Ensure every new table (`categories`, `tags`, `task_tags_map`) has strict Row-Level Security policies ensuring `user_id = auth.uid()`.
3. **Backend API Updates (`taskController.js`):**
   - Update the `GET /tasks` route to utilize Supabase relational queries (e.g., `.select('*, categories(*)')`) so the mobile app receives the full expanded payload.
4. **AI Orchestrator Updates (`aiController.js`):**
   - Update the vision parsing prompt logic to auto-assign a `task_type` (exam, assignment, general) based on context.

---

## 4. Definition of Done
- [ ] Supabase database contains the new columns and relational tables.
- [ ] No existing data in `tasks`, `primary_tasks`, or `sub_tasks` is deleted or corrupted.
- [ ] Row-Level Security (RLS) is active on all new architecture.
- [ ] The Node.js backend successfully fetches tasks with their associated categories and statuses.
