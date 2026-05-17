import { reportErrorEvent } from './errorTracking.js';

const normalizeError = (error) => {
  if (!error) return null;

  return {
    message: error.message || String(error),
    name: error.name || 'Error',
    stack: error.stack || null
  };
};

const logCounters = {
  info: 0,
  warn: 0,
  error: 0
};

export const getLogMetricsSnapshot = () => ({
  ...logCounters
});

export const log = (level, message, context = {}) => {
  const normalizedLevel = ['info', 'warn', 'error'].includes(level) ? level : 'info';

  const entry = {
    ts: new Date().toISOString(),
    level: normalizedLevel,
    message,
    ...context
  };

  if (context.error instanceof Error) {
    entry.error = normalizeError(context.error);
  }

  logCounters[normalizedLevel] += 1;

  if (normalizedLevel === 'error') {
    void reportErrorEvent(entry);
  }

  const line = JSON.stringify(entry);
  if (normalizedLevel === 'error' || normalizedLevel === 'warn') {
    console[normalizedLevel](line);
    return;
  }

  console.log(line);
};
