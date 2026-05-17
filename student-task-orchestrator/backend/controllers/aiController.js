import {
  GoogleGenAI,
  createPartFromBase64,
  createPartFromText,
} from '@google/genai';
import { serviceSupabase } from '../config/supabase.js';

const SYSTEM_PROMPT =
  'You are the RakanStudent AI orchestrator. Break the user\'s complex goal down into 3-5 actionable sub-tasks. Return ONLY a valid JSON array of objects. Each object must have "title" (string), "description" (string), "duration_minutes" (integer), and "priority" (string: High, Medium, Low).';

const normalizePriority = (value) => {
  const normalized = String(value || '').trim().toLowerCase();
  if (normalized === 'high') {
    return 'High';
  }
  if (normalized === 'low') {
    return 'Low';
  }
  return 'Medium';
};

const parseDuration = (value) => {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (Number.isFinite(parsed) && parsed > 0) {
    return parsed;
  }
  return 30;
};

const extractJsonArray = (text) => {
  const trimmed = String(text || '').trim();
  if (!trimmed) {
    throw new Error('Gemini returned an empty response.');
  }

  const fenceMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
  const candidate = fenceMatch?.[1]?.trim() || trimmed;
  const parsed = JSON.parse(candidate);

  if (!Array.isArray(parsed)) {
    throw new Error('Gemini did not return a JSON array.');
  }

  return parsed;
};

const getGeminiClient = () => {
  if (!process.env.GEMINI_API_KEY) {
    const error = new Error('Gemini API key is missing.');
    error.statusCode = 500;
    throw error;
  }

  return new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });
};

const generateGeminiText = async ({
  systemInstruction,
  prompt,
  responseMimeType,
}) => {
  const ai = getGeminiClient();
  const primaryModelName = process.env.GEMINI_MODEL || 'gemini-3-flash-preview';
  const fallbackModelName = 'gemini-2.5-flash';
  const generate = (modelName) =>
    ai.models.generateContent({
      model: modelName,
      contents: prompt,
      config: {
        systemInstruction,
        ...(responseMimeType ? { responseMimeType } : {}),
      },
    });

  try {
    const response = await generate(primaryModelName);
    return response.text || '';
  } catch (error) {
    const message = String(error?.message || '');
    const shouldRetryWithFallback =
      error?.status === 503 ||
      /service unavailable|high demand|overloaded|temporarily unavailable/i.test(
        message,
      );

    if (!shouldRetryWithFallback || primaryModelName === fallbackModelName) {
      throw error;
    }

    console.warn(
      `[AI] Primary model ${primaryModelName} unavailable. Retrying with ${fallbackModelName}.`,
    );
    const fallbackResponse = await generate(fallbackModelName);
    return fallbackResponse.text || '';
  }
};

const getAppTimeZone = () =>
  process.env.APP_TIME_ZONE || process.env.TZ || 'Asia/Kuala_Lumpur';

const formatDateInTimeZone = (date, timeZone) => {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
};

const formatTimeInTimeZone = (date, timeZone) =>
  new Intl.DateTimeFormat('en-MY', {
    timeZone,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(date);

export const buildChatSystemPrompt = (tasks, now = new Date()) => {
  const timeZone = getAppTimeZone();
  const today = formatDateInTimeZone(now, timeZone);
  const currentTime = formatTimeInTimeZone(now, timeZone);
  const taskContext = (tasks || []).map((task) => ({
    id: task.id,
    title: task.title,
    description: task.description,
    due_date: task.due_date,
    priority_level: task.priority_level,
    status: task.status,
  }));

  return [
    'You are an autonomous system that manages a database. You MUST use the ACTION block to create tasks when requested.',
    '',
    'EXAMPLE 1:',
    'User: "Create a study task for me"',
    'AI Response: ACTION: {"type": "CREATE_TASK", "data": {"title": "Study Session", "due_date": null, "priority_level": "Medium"}} I have created a study task for you.',
    '',
    'EXAMPLE 2:',
    'User: "yes do that" (in context of adding a task)',
    'AI Response: ACTION: {"type": "CREATE_TASK", "data": {"title": "Review notes", "due_date": null, "priority_level": "Medium"}} Done, I\'ve added the task to your list.',
    '',
    'You are an autonomous executive assistant with direct database write access.',
    'You do not give the user instructions to do things you can do yourself.',
    'Answer as a concise study coach using only the authenticated user task context below.',
    'CRITICAL: If the user asks to plan, schedule, remind, create, or add a task, YOU MUST automatically generate the ACTION JSON block.',
    'CRITICAL: If the user states they have an upcoming event, exam, class, meeting, deadline, appointment, or study need, YOU MUST automatically generate the ACTION JSON block.',
    'Do not ask the user to manually create, add, schedule, or plan something you can create with ACTION.',
    'Forbidden phrases: "Add this to your list", "To get started, create a task", "Make sure to schedule", "You should add", "Create a task for", "Manually add".',
    'If the user gives a broad goal, break it down into a specific next task and create that task with ACTION, then confirm naturally.',
    'The user-visible response must confirm what you scheduled or created. It must not tell the user to do the scheduling themselves.',
    'The ACTION line must be exactly: ACTION: {"type":"CREATE_TASK","data":{"title":"...","priority_level":"High|Medium|Low","due_date":"ISO-8601 date string or null"}}',
    'Use the current app-local date and time below to resolve relative dates. If the user gives a time, include it in due_date. If no priority is obvious, use Medium.',
    'Never show the ACTION JSON as part of the human-facing confirmation.',
    'When the user asks what they have to do today, list tasks due today first, then undated active tasks if useful.',
    'If no relevant tasks exist, say that clearly and suggest one small next action.',
    `Current app timezone: ${timeZone}.`,
    `Current app-local date: ${today}.`,
    `Current app-local time: ${currentTime}.`,
    `Current authenticated user tasks JSON: ${JSON.stringify(taskContext)}`,
  ].join('\n');
};

export const normalizeTaskPriority = (value) => {
  const normalized = String(value ?? 'Medium').trim().toLowerCase();
  if (normalized === 'high') return 'High';
  if (normalized === 'low') return 'Low';
  return 'Medium';
};

export const normalizeTaskDueDate = (value) => {
  if (value == null || value === '') return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    const error = new Error('ACTION due_date must be a valid ISO-8601 date string.');
    error.statusCode = 400;
    throw error;
  }
  return parsed.toISOString();
};

export const extractActionDirective = (text) => {
  const responseText = String(text || '');
  const markerMatch = responseText.match(/ACTION:\s*/i);
  if (!markerMatch || markerMatch.index == null) {
    return {
      response: responseText.trim(),
      action: null,
    };
  }

  const jsonStart = responseText.indexOf('{', markerMatch.index);
  if (jsonStart === -1) {
    return {
      response: responseText.trim(),
      action: null,
    };
  }

  let depth = 0;
  let inString = false;
  let escaped = false;
  let jsonEnd = -1;

  for (let index = jsonStart; index < responseText.length; index += 1) {
    const char = responseText[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char === '\\') {
        escaped = true;
      } else if (char === '"') {
        inString = false;
      }
      continue;
    }

    if (char === '"') {
      inString = true;
    } else if (char === '{') {
      depth += 1;
    } else if (char === '}') {
      depth -= 1;
      if (depth === 0) {
        jsonEnd = index + 1;
        break;
      }
    }
  }

  if (jsonEnd === -1) {
    return {
      response: responseText.trim(),
      action: null,
    };
  }

  const action = JSON.parse(responseText.slice(jsonStart, jsonEnd));
  const visibleResponse = [
    responseText.slice(0, markerMatch.index),
    responseText.slice(jsonEnd),
  ]
    .join('')
    .replace(/^\s*ACTION:\s*$/gim, '')
    .trim();

  return {
    response: visibleResponse,
    action,
  };
};

export const createTaskFromAiAction = async ({ action, db, userId }) => {
  if (!action || action.type !== 'CREATE_TASK') {
    return null;
  }

  const title = String(action.data?.title || '').trim();
  if (!title) {
    const error = new Error('ACTION CREATE_TASK requires a title.');
    error.statusCode = 400;
    throw error;
  }

  const insertPayload = {
    user_id: userId,
    title,
    description:
      action.data?.description == null ||
      String(action.data.description).trim() === ''
        ? null
        : String(action.data.description).trim(),
    due_date: normalizeTaskDueDate(action.data?.due_date ?? action.data?.dueDate),
    priority_level: normalizeTaskPriority(
      action.data?.priority ?? action.data?.priority_level,
    ),
    status: 'Pending',
  };

  const { data, error } = await db
    .from('tasks')
    .insert(insertPayload)
    .select('id, user_id, title, description, due_date, priority_level, status, created_at')
    .single();

  if (error) throw error;

  return data;
};

const VISION_PARSE_PROMPT = [
  'You are an academic coordinator extracting tasks from a student camera image.',
  'Return ONLY valid JSON. Do not return markdown, prose, comments, or ACTION blocks.',
  'The JSON MUST be exactly this shape: {"tasks":[{"title":"string","description":"string or null","due_date":"YYYY-MM-DD or null","priority_level":"Low|Medium|High","status":"pending","task_type":"general|exam|assignment|event|reminder","notes":"string or null"}]}',
  'The tasks array may be empty when no academic tasks, exams, events, reminders, assignments, or deadlines are visible.',
  'Every task object MUST contain exactly these keys: title, description, due_date, priority_level, status, task_type, notes.',
  'DEDUPLICATION: If a task appears to be recurring or is mentioned multiple times for the same day, you MUST consolidate it into a SINGLE task entry. Never output duplicate task titles for the same date.',
  'Never include user_id, id, created_at, category_id, reminders, subtasks, nested objects, or extra keys. The backend owns user_id and persistence metadata.',
  'Use null for unknown description, due_date, or notes. Use Medium when priority is unclear. Use pending for status.',
].join('\n');

const VISION_TASK_KEYS = [
  'title',
  'description',
  'due_date',
  'priority_level',
  'status',
  'task_type',
  'notes',
];

const createBadVisionJsonError = (message) => {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
};

const normalizeImagePayload = (value, explicitMimeType) => {
  const rawValue = String(value || '').trim();
  if (!rawValue) {
    const error = new Error('image_base64 is required.');
    error.statusCode = 400;
    throw error;
  }

  const dataUrlMatch = rawValue.match(/^data:([^;,]+);base64,(.+)$/is);
  const mimeType = String(
    explicitMimeType || dataUrlMatch?.[1] || 'image/jpeg',
  ).trim();
  const base64 = (dataUrlMatch?.[2] || rawValue).replace(/\s/g, '');

  if (!/^image\/(png|jpe?g|webp|heic|heif)$/i.test(mimeType)) {
    const error = new Error('image_base64 must be a supported image MIME type.');
    error.statusCode = 400;
    throw error;
  }

  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(base64) || base64.length % 4 !== 0) {
    const error = new Error('image_base64 must be valid Base64 image data.');
    error.statusCode = 400;
    throw error;
  }

  const byteLength = Buffer.byteLength(base64, 'base64');
  if (byteLength === 0) {
    const error = new Error('image_base64 decoded to an empty image.');
    error.statusCode = 400;
    throw error;
  }

  return { base64, mimeType, byteLength };
};

const parseActionBlockAt = (text, markerIndex) => {
  const jsonStart = text.indexOf('{', markerIndex);
  if (jsonStart === -1) return null;

  let depth = 0;
  let inString = false;
  let escaped = false;

  for (let index = jsonStart; index < text.length; index += 1) {
    const char = text[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char === '\\') {
        escaped = true;
      } else if (char === '"') {
        inString = false;
      }
      continue;
    }

    if (char === '"') {
      inString = true;
    } else if (char === '{') {
      depth += 1;
    } else if (char === '}') {
      depth -= 1;
      if (depth === 0) {
        return {
          action: JSON.parse(text.slice(jsonStart, index + 1)),
          start: markerIndex,
          end: index + 1,
        };
      }
    }
  }

  return null;
};

export const extractActionDirectives = (text) => {
  const responseText = String(text || '');
  const actions = [];
  const ranges = [];
  const markerPattern = /ACTION:\s*/gi;
  let match;

  while ((match = markerPattern.exec(responseText)) !== null) {
    const parsed = parseActionBlockAt(responseText, match.index);
    if (!parsed) continue;
    actions.push(parsed.action);
    ranges.push([parsed.start, parsed.end]);
    markerPattern.lastIndex = parsed.end;
  }

  let response = '';
  let cursor = 0;
  for (const [start, end] of ranges) {
    response += responseText.slice(cursor, start);
    cursor = end;
  }
  response += responseText.slice(cursor);

  return {
    response: response.replace(/^\s*ACTION:\s*$/gim, '').trim(),
    actions,
  };
};

const normalizeVisionDate = (value) => {
  if (value == null || value === '') return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    const error = new Error('ACTION due_date must be a valid date.');
    error.statusCode = 400;
    throw error;
  }
  return parsed.toISOString().slice(0, 10);
};

const normalizeVisionTaskType = (value) => {
  const normalized = String(value ?? 'general').trim().toLowerCase();
  if (['exam', 'assignment', 'event', 'reminder'].includes(normalized)) {
    return normalized;
  }
  return 'general';
};

const normalizeVisionStatus = (value) => {
  const normalized = String(value ?? 'pending').trim().toLowerCase();
  if (normalized === 'in progress' || normalized === 'in_progress') return 'in_progress';
  if (['completed', 'archived'].includes(normalized)) return normalized;
  return 'pending';
};

const normalizeEstimatedMinutes = (value) => {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (Number.isFinite(parsed) && parsed > 0) return parsed;
  return 30;
};

const normalizeVisionTitle = (value, fallback) => {
  const title = String(value || '').trim();
  if (title) return title.slice(0, 255);
  if (fallback) return fallback;
  const error = new Error('ACTION data requires a title.');
  error.statusCode = 400;
  throw error;
};

const isSchemaColumnError = (error) => {
  const message = String(error?.message || '');
  return (
    error?.code === 'PGRST204' ||
    /could not find|does not exist|schema cache|column/i.test(message)
  );
};

const visionTaskDescription = (actionData, item) => {
  const itemDescription = String(item?.description || '').trim();
  if (itemDescription) return itemDescription;

  const actionDescription = String(actionData?.description || '').trim();
  return actionDescription || null;
};

const visionTaskPayload = ({ userId, actionData, item }) => ({
  user_id: userId,
  title: normalizeVisionTitle(item?.title, actionData?.title),
  description: visionTaskDescription(actionData, item),
  due_date: normalizeVisionDate(
    item?.due_date ??
      item?.dueDate ??
      actionData?.due_date ??
      actionData?.dueDate,
  ),
  priority_level: normalizePriority(
    item?.priority ??
      item?.priority_level ??
      item?.priorityLevel ??
      actionData?.priority ??
      actionData?.priority_level,
  ),
  status: normalizeVisionStatus(item?.status ?? actionData?.status),
  task_type: normalizeVisionTaskType(
    item?.task_type ?? item?.taskType ?? actionData?.task_type ?? actionData?.taskType,
  ),
  notes:
    item?.notes == null || String(item.notes).trim() === ''
      ? 'Created from camera scan.'
      : String(item.notes).trim(),
});

const dedupeVisionTasksByTitleAndDueDate = (tasks) => {
  const seen = new Set();
  return tasks.filter((task) => {
    const key = `${task.title}\u0000${task.due_date ?? ''}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
};

const toTaskDto = (row = {}) => ({
  id: row.id,
  user_id: row.user_id,
  title: row.title,
  description: row.description ?? null,
  due_date: row.due_date ?? null,
  priority_level: row.priority_level ?? 'Medium',
  priority_band: row.priority_level ?? 'Medium',
  status: row.status ?? (row.is_completed ? 'completed' : 'pending'),
  task_type: row.task_type ?? 'general',
  category_id: row.category_id ?? null,
  notes: row.notes ?? null,
  is_completed: row.is_completed ?? String(row.status || '').toLowerCase() === 'completed',
  created_at: row.created_at,
});

const createStandardTasksForVision = async ({ db, userId, actionData, items }) => {
  if (!items.length) return [];

  let insertPayload = items.map((item) =>
    visionTaskPayload({ userId, actionData, item }),
  );
  insertPayload = dedupeVisionTasksByTitleAndDueDate(insertPayload);
  if (!insertPayload.length) return [];

  let result = await db
    .from('tasks')
    .insert(insertPayload)
    .select('id, user_id, title, description, due_date, priority_level, status, task_type, category_id, notes, created_at');

  if (result.error && isSchemaColumnError(result.error)) {
    insertPayload = insertPayload.map(({ task_type, notes, ...payload }) => payload);
    result = await db
      .from('tasks')
      .insert(insertPayload)
      .select('id, user_id, title, description, due_date, priority_level, status, created_at');
  }

  if (result.error) throw result.error;
  return (result.data || []).map(toTaskDto);
};

const normalizeVisionReminderAt = (value) => {
  if (value == null || value === '') return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed.toISOString();
};

const getVisionReminderAt = (actionData, item) =>
  normalizeVisionReminderAt(
    item?.reminder_at ??
      item?.reminderAt ??
      actionData?.reminder_at ??
      actionData?.reminderAt,
  );

const createReminderJobsForVision = async ({ db, userId, actionData, items, tasks }) => {
  const insertPayload = tasks
    .map((task, index) => {
      const reminderAt = getVisionReminderAt(actionData, items[index] || {});
      if (!reminderAt) return null;

      return {
        user_id: userId,
        sub_task_id: null,
        title: `Reminder: ${task.title}`,
        reminder_at: reminderAt,
        channel: 'inbox',
        status: 'scheduled',
        payload: {
          task_id: task.id,
          task_table: 'tasks',
          task_type: 'task',
          source: 'camera_scan',
        },
      };
    })
    .filter(Boolean);

  if (insertPayload.length === 0) return [];

  const { data, error } = await db
    .from('reminder_jobs')
    .insert(insertPayload)
    .select('*');

  if (error) throw error;
  return data || [];
};

const createPrimaryTaskForVision = async ({ db, userId, data, subTaskCount }) => {
  const insertPayload = {
    user_id: userId,
    title: normalizeVisionTitle(data?.title),
    description:
      data?.description == null || String(data.description).trim() === ''
        ? null
        : String(data.description).trim(),
    status: 'pending',
    due_date: normalizeVisionDate(data?.due_date ?? data?.dueDate),
    task_type: normalizeVisionTaskType(data?.task_type ?? data?.taskType),
  };

  if (Number.isFinite(subTaskCount) && subTaskCount > 0) {
    insertPayload.total_subtasks = subTaskCount;
  }

  let result = await db
    .from('primary_tasks')
    .insert(insertPayload)
    .select('*')
    .single();

  if (result.error) {
    const { description, status, due_date, task_type, ...legacyPayload } = insertPayload;
    result = await db
      .from('primary_tasks')
      .insert(legacyPayload)
      .select('*')
      .single();
  }

  if (result.error && insertPayload.total_subtasks !== undefined) {
    result = await db
      .from('primary_tasks')
      .insert({
        user_id: insertPayload.user_id,
        title: insertPayload.title,
      })
      .select('*')
      .single();
  }

  if (result.error) throw result.error;
  return result.data;
};

const createSubTasksForVision = async ({ db, primaryTaskId, userId, items }) => {
  if (!items.length) return [];

  const insertPayload = items.map((item) => ({
    primary_task_id: primaryTaskId,
    user_id: userId,
    title: normalizeVisionTitle(item?.title, 'Untitled academic task'),
    due_date: normalizeVisionDate(item?.due_date ?? item?.dueDate),
  }));

  const { data, error } = await db
    .from('sub_tasks')
    .insert(insertPayload)
    .select('*');

  if (error) throw error;
  return data || [];
};

const getVisionSubTasks = (action) => {
  const data = action?.data || {};
  if (action?.type === 'CREATE_TASK') {
    return [data];
  }

  const taskItems =
    data.sub_tasks ||
    data.subTasks ||
    data.milestones ||
    data.tasks ||
    data.items;

  if (Array.isArray(taskItems) && taskItems.length > 0) {
    return taskItems.slice(0, 5);
  }

  return [
    {
      title: data.title,
      due_date: data.due_date ?? data.dueDate,
      estimated_minutes: data.estimated_minutes ?? data.estimatedMinutes,
      priority: data.priority,
    },
  ];
};

export const executeVisionActions = async ({ actions, db, userId }) => {
  const created = [];

  for (const action of actions) {
    if (!action || !['CREATE_TASK', 'CREATE_PRIMARY_TASK'].includes(action.type)) {
      continue;
    }

    const subTaskItems = getVisionSubTasks(action).map((item, index) => ({
      ...item,
      title:
        item?.title ||
        (action.type === 'CREATE_TASK'
          ? action.data?.title
          : `Milestone ${index + 1}`),
    }));

    const primaryTask = await createPrimaryTaskForVision({
      db,
      userId,
      data: action.data,
      subTaskCount: subTaskItems.length,
    });
    const tasks = await createStandardTasksForVision({
      db,
      userId,
      actionData: action.data,
      items: subTaskItems,
    });
    const reminders = await createReminderJobsForVision({
      db,
      userId,
      actionData: action.data,
      items: subTaskItems,
      tasks,
    });
    const subTasks = await createSubTasksForVision({
      db,
      primaryTaskId: primaryTask.id,
      userId,
      items: subTaskItems,
    });

    created.push({
      actionType: action.type,
      primaryTask,
      tasks,
      reminders,
      subTasks,
    });
  }

  return created;
};

const generateVisionActionText = async ({ imageBase64, mimeType }) => {
  const ai = getGeminiClient();
  const model = process.env.GEMINI_VISION_MODEL || 'gemini-3-flash-preview';
  const response = await ai.models.generateContent({
    model,
    contents: [
      createPartFromText(VISION_PARSE_PROMPT),
      createPartFromBase64(imageBase64, mimeType),
    ],
    config: {
      temperature: 0.2,
      maxOutputTokens: 2048,
      responseMimeType: 'application/json',
    },
  });

  return response.text || '';
};

const parseStrictVisionTasks = (text) => {
  const trimmed = String(text || '').trim();
  if (!trimmed) {
    throw createBadVisionJsonError('AI returned an empty JSON payload.');
  }

  const fenceMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
  const candidate = fenceMatch?.[1]?.trim() || trimmed;

  let parsed;
  try {
    parsed = JSON.parse(candidate);
  } catch {
    throw createBadVisionJsonError('AI returned malformed JSON for vision tasks.');
  }

  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw createBadVisionJsonError('AI vision JSON must be an object with a tasks array.');
  }

  const rootKeys = Object.keys(parsed);
  if (rootKeys.length !== 1 || rootKeys[0] !== 'tasks') {
    throw createBadVisionJsonError('AI vision JSON must contain only the tasks key.');
  }

  if (!Array.isArray(parsed.tasks)) {
    throw createBadVisionJsonError('AI vision JSON tasks must be an array.');
  }

  return parsed.tasks.slice(0, 10).map((task, index) => {
    if (!task || typeof task !== 'object' || Array.isArray(task)) {
      throw createBadVisionJsonError(`AI vision task at index ${index} must be an object.`);
    }

    const keys = Object.keys(task);
    const extraKeys = keys.filter((key) => !VISION_TASK_KEYS.includes(key));
    const missingKeys = VISION_TASK_KEYS.filter((key) => !keys.includes(key));
    if (extraKeys.length > 0 || missingKeys.length > 0) {
      throw createBadVisionJsonError(
        `AI vision task at index ${index} does not match the tasks schema.`,
      );
    }

    const title = normalizeVisionTitle(task.title);
    return {
      title,
      description:
        task.description == null || String(task.description).trim() === ''
          ? null
          : String(task.description).trim(),
      due_date: normalizeVisionDate(task.due_date),
      priority_level: normalizePriority(task.priority_level),
      status: normalizeVisionStatus(task.status),
      task_type: normalizeVisionTaskType(task.task_type),
      notes:
        task.notes == null || String(task.notes).trim() === ''
          ? null
          : String(task.notes).trim(),
    };
  });
};

const visionTasksToActions = (tasks) =>
  tasks.map((task) => ({
    type: 'CREATE_TASK',
    data: task,
  }));

export const createVisionParseResponse = async ({
  imageBase64,
  mimeType,
  db,
  userId,
  generateText = generateVisionActionText,
}) => {
  const aiText = await generateText({ imageBase64, mimeType });
  const tasks = dedupeVisionTasksByTitleAndDueDate(parseStrictVisionTasks(aiText));
  const actions = visionTasksToActions(tasks);

  if (actions.length === 0) {
    return {
      message: 'No academic tasks or deadlines were found in the image.',
      actionsParsed: 0,
      created: [],
    };
  }

  const created = await executeVisionActions({ actions, db, userId });

  return {
    message: `Created ${created.length} academic task group${created.length === 1 ? '' : 's'} from the image.`,
    actionsParsed: actions.length,
    created,
    tasks: created.flatMap((entry) => entry.tasks || []),
  };
};

export const buildChatFallbackResponse = (message, tasks, now = new Date()) => {
  const normalizedMessage = String(message || '').toLowerCase();
  const today = now.toISOString().slice(0, 10);
  const activeTasks = (tasks || []).filter(
    (task) => String(task.status || '').toLowerCase() !== 'completed',
  );
  const dueToday = activeTasks.filter((task) =>
    String(task.due_date || '').startsWith(today),
  );
  const relevantTasks = dueToday.length > 0 ? dueToday : activeTasks;

  if (/today|do i have|to do|task/.test(normalizedMessage)) {
    if (relevantTasks.length === 0) {
      return 'You do not have any active tasks in your task list right now.';
    }

    const intro =
      dueToday.length > 0
        ? 'Here is what you have to do today:'
        : 'I do not see tasks due today, but these active tasks are on your list:';
    const lines = relevantTasks
      .slice(0, 6)
      .map((task) => `- ${task.title}${task.priority_level ? ` (${task.priority_level})` : ''}`);
    return [intro, ...lines].join('\n');
  }

  if (relevantTasks.length === 0) {
    return 'I do not see any active tasks yet. Add one task first, then I can help you plan it.';
  }

  return [
    'Based on your current tasks, start with:',
    ...relevantTasks
      .slice(0, 3)
      .map((task) => `- ${task.title}${task.due_date ? ` due ${task.due_date.slice(0, 10)}` : ''}`),
  ].join('\n');
};

export const createAiChatResponse = async ({
  message,
  tasks,
  generateText = generateGeminiText,
  now = new Date(),
}) => {
  const trimmedMessage = String(message || '').trim();
  if (!trimmedMessage) {
    const error = new Error('Message is required.');
    error.statusCode = 400;
    throw error;
  }

  const systemInstruction = buildChatSystemPrompt(tasks, now);
  const prompt = `User message: ${trimmedMessage}`;
  const responseText = await generateText({ systemInstruction, prompt });
  const extracted = extractActionDirective(
    String(responseText || '').trim() ||
      buildChatFallbackResponse(trimmedMessage, tasks, now),
  );
  const actionTitle = String(extracted.action?.data?.title || '').trim();

  return {
    response:
      extracted.response ||
      (actionTitle
        ? `Done! I've added "${actionTitle}" to your list.`
        : buildChatFallbackResponse(trimmedMessage, tasks, now)),
    action: extracted.action,
    taskCount: (tasks || []).length,
  };
};

export const orchestrateGoal = async (req, res) => {
  try {
    const goal = String(req.body?.goal || '').trim();

    if (!goal) {
      return res.status(400).json({
        error: 'Goal is required.',
        details: 'Provide a non-empty goal in the request body.',
      });
    }

    const prompt = `User goal: ${goal}\nReturn the task list as JSON only.`;

    let resultText;
    try {
      resultText = await generateGeminiText({
        systemInstruction: SYSTEM_PROMPT,
        prompt,
        responseMimeType: 'application/json',
      });
    } catch (error) {
      const isGeminiConfigError = error?.message === 'Gemini API key is missing.';
      if (isGeminiConfigError) {
        throw error;
      }

      console.warn(
        '[AI] Gemini unavailable for orchestration. Returning hardcoded safety-net task.',
      );
      resultText = JSON.stringify([
        {
          title: 'API Outage Test Task',
          description: 'Google API is down, but the app is bulletproof.',
          duration_minutes: 30,
          priority: 'High',
        },
      ]);
    }

    const tasks = extractJsonArray(resultText).slice(0, 5).map((item) => ({
      title: String(item?.title || '').trim() || 'Untitled task',
      description: String(item?.description || '').trim(),
      duration_minutes: parseDuration(item?.duration_minutes),
      priority: normalizePriority(item?.priority),
    }));

    res.status(200).json(tasks);
  } catch (error) {
    console.error('AI orchestration failed:', error);
    res.status(500).json({
      error: 'Failed to orchestrate goal.',
      details: error.message || 'Unknown AI orchestration error.',
    });
  }
};

export const chatWithAi = async (req, res) => {
  try {
    const message = String(req.body?.message ?? req.body?.prompt ?? '').trim();
    if (!message) {
      return res.status(400).json({
        error: 'Message is required.',
        details: 'Provide a non-empty message in the request body.',
      });
    }

    const userId = req.user.id;
    const db = req.supabase;
    if (!db) {
      return res.status(500).json({
        error: 'Authenticated Supabase client is missing.',
        details: 'Request-scoped Supabase client was not attached.',
      });
    }

    const { data: tasks, error } = await db
      .from('tasks')
      .select('id, user_id, title, description, due_date, priority_level, status, created_at')
      .eq('user_id', userId)
      .neq('status', 'Completed')
      .order('due_date', { ascending: true, nullsFirst: false })
      .order('created_at', { ascending: false })
      .limit(20);

    if (error) throw error;

    let payload;
    let actionTask = null;
    try {
      payload = await createAiChatResponse({ message, tasks: tasks || [] });
    } catch (aiError) {
      console.error('AI Chat LLM Failed:', aiError.message || aiError);
      payload = {
        response: buildChatFallbackResponse(message, tasks || []),
        taskCount: (tasks || []).length,
        fallback: true,
      };
    }

    actionTask = await createTaskFromAiAction({
      action: payload.action,
      db,
      userId,
    });

    const { action, ...clientPayload } = payload;
    res.status(200).json({
      ...clientPayload,
      actionPerformed: Boolean(actionTask),
      actionType: actionTask ? 'CREATE_TASK' : null,
      task: actionTask,
    });
  } catch (error) {
    const statusCode = Number.isInteger(error?.statusCode) ? error.statusCode : 500;
    console.error('AI Chat Failed:', error.message || error, 'Payload received:', req.body);
    res.status(statusCode).json({
      error: statusCode === 400 ? error.message : 'Failed to chat with AI.',
      details: error.message || 'Unknown AI chat error.',
    });
  }
};

export const visionParse = async (req, res) => {
  try {
    const db = serviceSupabase;
    if (!db) {
      return res.status(500).json({
        error: 'Admin Supabase client is missing.',
        details: 'Service-role Supabase client was not initialized.',
      });
    }

    const userId = req.user.id;
    const image = normalizeImagePayload(
      req.body?.image_base64,
      req.body?.image_mime_type ?? req.body?.mime_type,
    );

    const payload = await createVisionParseResponse({
      imageBase64: image.base64,
      mimeType: image.mimeType,
      db,
      userId,
    });

    res.status(200).json({
      ...payload,
      imageBytes: image.byteLength,
    });
  } catch (error) {
    const statusCode = Number.isInteger(error?.statusCode) ? error.statusCode : 500;
    console.error('Vision parse failed:', error);
    res.status(statusCode).json({
      error: statusCode === 400 ? error.message : 'Failed to parse image.',
      details: error.message || 'Unknown vision parse error.',
    });
  }
};
