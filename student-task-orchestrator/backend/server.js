import 'dotenv/config';
import { createRequire } from 'module';
import express from 'express';
import cors from 'cors';
import multer from 'multer';
import * as dns from 'node:dns';
import { GoogleGenAI } from '@google/genai';
import taskRoutes from './routes/tasks.js';
import { createSupabaseForToken, runWithSupabase, supabase } from './config/supabase.js';
import { getOperationsMetricsSnapshot, recordHttpRequest } from './lib/operationsMetrics.js';
import { attachRequestContext } from './lib/requestContext.js';
import { requireAuth } from './middleware/authMiddleware.js';
import scheduleRoutes from './routes/schedule.js';
import calendarRoutes from './routes/calendar.js';
import driveRoutes from './routes/drive.js';
import orchestrationRoutes from './routes/orchestration.js';
import analyticsRoutes from './routes/analytics.js';
import workspaceRoutes from './routes/workspaces.js';
import settingsRoutes from './routes/settings.js';
import pipelineRoutes from './routes/pipeline.js';
import aiRoutes from './routes/ai.js';
import focusRoutes from './routes/focus.js';
import { completeCalendarOAuthCallback } from './controllers/calendarController.js';
import { completeDriveOAuthCallback } from './controllers/driveController.js';
import { startCalendarSyncLoop, validateCalendarConfig } from './lib/calendarService.js';
import { startNotificationDispatchLoop } from './lib/notificationService.js';
import { getSystemReadinessSnapshot } from './lib/systemReadiness.js';

// Validate required environment configuration on startup
try {
  validateCalendarConfig();
} catch (err) {
  console.error('[FATAL]', err.message);
  process.exit(1);
}

const require = createRequire(import.meta.url);
const { PDFParse } = require('pdf-parse');

const app = express();
const PORT = 5000;
const upload = multer({ storage: multer.memoryStorage() });

const extractJsonArray = (text) => {
  const trimmed = String(text || '').trim();
  if (!trimmed) {
    throw new Error('AI returned an empty response.');
  }

  const fenceMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
  const candidate = fenceMatch?.[1]?.trim() || trimmed;
  const parsed = JSON.parse(candidate);

  if (!Array.isArray(parsed)) {
    throw new Error('AI did not return a JSON array.');
  }

  return parsed.map((item) => ({
    subject: String(item?.subject || 'TBA'),
    day: String(item?.day || 'TBA'),
    time: String(item?.time || 'TBA'),
    location: String(item?.location || 'TBA'),
    lecturer: String(item?.lecturer || 'TBA')
  }));
};

const subjectCode = (value) => {
  const text = String(value || '').trim().toUpperCase();
  const match = text.match(/[A-Z]{2,}\s*\d{3,}[A-Z0-9]*/);
  return (match?.[0] || text).replace(/\s+/g, '');
};

const firstLecturer = (value) => {
  const names = String(value || '')
    .split(/\s*(?:,|\/|&|\band\b)\s*/i)
    .map((name) => name.trim())
    .filter(Boolean);
  return names[0] || 'TBA';
};

const uniqueBySubjectCode = (classes) => {
  const unique = new Map();
  for (const item of classes) {
    const code = subjectCode(item.subject);
    if (!code || code === 'TBA' || unique.has(code)) continue;
    unique.set(code, {
      ...item,
      subject: code,
      lecturer: firstLecturer(item.lecturer)
    });
  }
  return [...unique.values()];
};

const parseClassesHeuristically = (rawText) => {
  const days = '(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Wed|Thu|Fri|Sat|Sun)';
  const time = '(\\d{1,2}:\\d{2}\\s*(?:AM|PM|am|pm)?(?:\\s*[-–—]\\s*\\d{1,2}:\\d{2}\\s*(?:AM|PM|am|pm)?)?)';
  const lines = String(rawText || '')
    .replace(/\s{2,}/g, '\n')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

  return lines.flatMap((line) => {
    const regex = new RegExp(`([^\\n]*?)\\s+${days}\\s+${time}\\s+([^\\n]+?)(?=\\s+[^\\n]*?\\s+${days}\\s+${time}\\s+|$)`, 'gi');
    const classes = [];
    let match;

    while ((match = regex.exec(line)) != null) {
      const tail = match[4].trim();
      const lecturerMatch = tail.match(/(Dr\.?|Mr\.?|Ms\.?|Mrs\.?|Prof\.?)\s+.+$/i);
      const lecturer = lecturerMatch?.[0]?.trim() || 'TBA';
      const location = lecturerMatch
        ? tail.slice(0, lecturerMatch.index).trim() || 'TBA'
        : tail || 'TBA';

      classes.push({
      subject: subjectCode(match[1].trim()) || 'TBA',
      day: match[2].trim() || 'TBA',
      time: match[3].trim() || 'TBA',
      location,
      lecturer: firstLecturer(lecturer)
      });
    }

    return classes;
  });
};

const extractClassesFromText = async (rawText) => {
  if (!process.env.GEMINI_API_KEY) {
    return parseClassesHeuristically(rawText);
  }

  const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });
  const prompt = [
    'You are an expert university timetable parser.',
    'Extract every class session from the timetable text below.',
    'Do not stop after the first row. Return every class row/session you can find.',
    'Return ONLY a valid JSON array. Do not include markdown or explanations.',
    'Every object must have exactly these string fields: subject, day, time, location, lecturer.',
    'For time, preserve the full range if present, for example "08:30 AM - 10:30 AM".',
    'If a field is missing, use "TBA".',
    '',
    'Timetable text:',
    rawText
  ].join('\n');
  const modelNames = [
    process.env.GEMINI_MODEL || 'gemini-3.1-pro-preview',
    'gemini-3.1-pro-preview'
  ];
  let lastError;

  for (const model of [...new Set(modelNames)]) {
    try {
      const response = await ai.models.generateContent({
        model,
        contents: prompt,
        config: { responseMimeType: 'application/json' }
      });

      return uniqueBySubjectCode(extractJsonArray(response.text || ''));
    } catch (error) {
      lastError = error;
      console.warn(`[AI] Timetable extraction failed on ${model}:`, error.message);
    }
  }

  const fallbackClasses = parseClassesHeuristically(rawText);
  if (fallbackClasses.length > 0) {
    return uniqueBySubjectCode(fallbackClasses);
  }

  throw lastError || new Error('Timetable extraction failed.');
};

app.use(cors({
  origin: '*',
  exposedHeaders: ['x-request-id', 'retry-after']
}));
app.use(express.json({ limit: '16mb' }));
app.use((req, res, next) => {
    console.log(`[ALERT] Incoming Request: ${req.method} ${req.originalUrl}`);
    next();
});
app.use((req, res, next) => {
  res.on('finish', () => {
    recordHttpRequest({
      method: req.method,
      statusCode: res.statusCode
    });
  });

  next();
});

app.get('/api/timetable/parse', (req, res) => {
  res.status(200).send('✅ ROUTE IS ALIVE AND REACHABLE!');
});

app.post('/api/timetable/parse', upload.single('file'), async (req, res) => {
  console.log('====================================');
  console.log('📥 Received timetable file for parsing...');
  console.log('====================================');

  if (!req.file) {
    return res.status(400).json({ error: 'No file uploaded from Flutter.' });
  }

  const originalName = req.file.originalname || '';
  const isPdf = req.file.mimetype === 'application/pdf' || originalName.toLowerCase().endsWith('.pdf');
  if (!isPdf) {
    return res.status(415).json({
      error: 'Unsupported timetable file type',
      details: 'Only PDF timetable uploads are supported right now. Please upload a .pdf file.'
    });
  }

  let parser;
  try {
    parser = new PDFParse({ data: req.file.buffer });
    const parsed = await parser.getText();
    const rawText = parsed.text || '';

    if (!rawText.trim()) {
      return res.status(200).json({ success: true, message: 'PDF was empty', data: [] });
    }

    console.log('✅ PDF text extracted successfully.');
    const extractedClasses = await extractClassesFromText(rawText);

    return res.status(200).json({
      success: true,
      message: 'LangGraph parsing complete.',
      data: extractedClasses
    });
  } catch (error) {
    console.error('❌ Timetable parsing failure:', error);
    return res.status(500).json({
      error: 'Failed to parse PDF document',
      details: error.message
    });
  } finally {
    if (parser) {
      await parser.destroy();
    }
  }
});

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.status(200).json({ status: 'ok', message: 'Backend is running correctly.' });
});

app.get('/api/health/readiness', async (req, res) => {
  const report = await getSystemReadinessSnapshot();
  const statusCode = report.status === 'ready' ? 200 : report.status === 'degraded' ? 206 : 503;
  res.status(statusCode).json(report);
});

app.get('/api/health/metrics', async (req, res) => {
  const snapshot = await getOperationsMetricsSnapshot();
  const statusCode = snapshot.redis.reachable ? 200 : 206;
  res.status(statusCode).json(snapshot);
});

// Supabase heartbeat endpoint
app.get('/api/health/supabase', async (req, res) => {
  try {
    const { data, error } = await supabase.from('primary_tasks').select('id').limit(1);
    if (error) throw error;
    res.status(200).json({ status: 'ok', message: 'Neural Link to Supabase is active.', details: data });
  } catch (error) {
    console.error("Supabase Heartbeat Failure:", error);
    res.status(500).json({ status: 'error', message: 'Neural Link failure.', details: error.message });
  }
});

app.get('/api/calendar/oauth/callback', attachRequestContext, completeCalendarOAuthCallback);
app.get('/api/calendar/google/callback', attachRequestContext, completeCalendarOAuthCallback);
app.get('/api/drive/oauth/callback', attachRequestContext, completeDriveOAuthCallback);
app.get('/api/drive/google/callback', attachRequestContext, completeDriveOAuthCallback);
app.use('/api', (req, res, next) => {
  const token = req.headers.authorization?.split(' ')[1];
  if (token) {
    const requestSupabase = createSupabaseForToken(token);
    req.supabaseToken = token;
    req.supabase = requestSupabase;
    runWithSupabase(requestSupabase, next);
    return;
  }
  next();
});
app.use('/api', attachRequestContext);
app.use('/api', requireAuth);

app.use('/api/tasks', taskRoutes);
app.use('/api/schedule', scheduleRoutes);
app.use('/api/calendar', calendarRoutes);
app.use('/api/drive', driveRoutes);
app.use('/api/orchestration', orchestrationRoutes);
app.use('/api/analytics', analyticsRoutes);
app.use('/api/workspaces', workspaceRoutes);
app.use('/api/settings', settingsRoutes);
app.use('/api/pipeline', pipelineRoutes);
app.use('/api/ai', aiRoutes);
app.use('/api/focus', focusRoutes);

const supaUrl = new URL(process.env.SUPABASE_URL || 'https://localhost');
try {
  const address = await dns.promises.lookup(supaUrl.hostname);
  console.log(`[OK] Supabase resolved to IP: ${address.address}`);
} catch (err) {
  console.error("[FATAL] Cannot resolve Supabase DNS. Is the project paused?", err.message);
  process.exit(1);
}

app.listen(5000, '0.0.0.0', () => {
  startCalendarSyncLoop();
  startNotificationDispatchLoop();
  console.log("Server running on port 5000 (0.0.0.0)");
  console.log(`Backend live at http://0.0.0.0:${PORT}/api`);
});
