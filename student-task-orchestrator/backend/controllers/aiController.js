import { GoogleGenerativeAI } from '@google/generative-ai';

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

  return new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
};

const generateGeminiText = async ({
  systemInstruction,
  prompt,
  responseMimeType,
}) => {
  const genAI = getGeminiClient();
  const primaryModelName = process.env.GEMINI_MODEL || 'gemini-3-flash-preview';
  const fallbackModelName = 'gemini-2.5-flash';
  const createModel = (modelName) =>
    genAI.getGenerativeModel({
      model: modelName,
      systemInstruction,
      generationConfig: {
        ...(responseMimeType ? { responseMimeType } : {}),
      },
    });

  try {
    const result = await createModel(primaryModelName).generateContent(prompt);
    const response = await result.response;
    return response.text();
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
    const fallbackResult =
      await createModel(fallbackModelName).generateContent(prompt);
    const fallbackResponse = await fallbackResult.response;
    return fallbackResponse.text();
  }
};

export const buildChatSystemPrompt = (tasks, now = new Date()) => {
  const today = now.toISOString().slice(0, 10);
  const taskContext = (tasks || []).map((task) => ({
    id: task.id,
    title: task.title,
    description: task.description,
    due_date: task.due_date,
    priority_level: task.priority_level,
    status: task.status,
  }));

  return [
    'You are the RakanStudent AI task assistant.',
    'Answer as a concise study coach using only the authenticated user task context below.',
    'When the user asks what they have to do today, list tasks due today first, then undated active tasks if useful.',
    'If no relevant tasks exist, say that clearly and suggest one small next action.',
    `Today is ${today}.`,
    `Current authenticated user tasks JSON: ${JSON.stringify(taskContext)}`,
  ].join('\n');
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

  return {
    response:
      String(responseText || '').trim() ||
      buildChatFallbackResponse(trimmedMessage, tasks, now),
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

    res.status(200).json(payload);
  } catch (error) {
    const statusCode = Number.isInteger(error?.statusCode) ? error.statusCode : 500;
    console.error('AI Chat Failed:', error.message || error, 'Payload received:', req.body);
    res.status(statusCode).json({
      error: statusCode === 400 ? error.message : 'Failed to chat with AI.',
      details: error.message || 'Unknown AI chat error.',
    });
  }
};
