import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import * as dns from 'node:dns';
import taskRoutes from './routes/tasks.js';
import { createSupabaseForToken, runWithSupabase, supabase } from './config/supabase.js';
import { getOperationsMetricsSnapshot, recordHttpRequest } from './lib/operationsMetrics.js';
import { attachRequestContext } from './lib/requestContext.js';
import { requireAuth } from './middleware/authMiddleware.js';
import scheduleRoutes from './routes/schedule.js';
import calendarRoutes from './routes/calendar.js';
import orchestrationRoutes from './routes/orchestration.js';
import analyticsRoutes from './routes/analytics.js';
import workspaceRoutes from './routes/workspaces.js';
import settingsRoutes from './routes/settings.js';
import pipelineRoutes from './routes/pipeline.js';
import aiRoutes from './routes/ai.js';
import { completeCalendarOAuthCallback } from './controllers/calendarController.js';
import { startCalendarSyncLoop } from './lib/calendarService.js';
import { startNotificationDispatchLoop } from './lib/notificationService.js';
import { getSystemReadinessSnapshot } from './lib/systemReadiness.js';

const app = express();
const PORT = 5000;

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
app.use('/api/orchestration', orchestrationRoutes);
app.use('/api/analytics', analyticsRoutes);
app.use('/api/workspaces', workspaceRoutes);
app.use('/api/settings', settingsRoutes);
app.use('/api/pipeline', pipelineRoutes);
app.use('/api/ai', aiRoutes);

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
