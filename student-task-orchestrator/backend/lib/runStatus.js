export const RUN_KINDS = {
  ASSIGNMENT_BREAKDOWN: 'assignment_breakdown',
  SUBTASK_BREAKDOWN: 'subtask_breakdown',
  SCHEDULE_REBUILD: 'schedule_rebuild',
  SYLLABUS_PARSE: 'syllabus_parse',
  TIMETABLE_EXTRACT: 'timetable_extract'
};

export const RUN_STATUSES = {
  QUEUED: 'QUEUED',
  PROCESSING: 'PROCESSING',
  COMPLETED: 'COMPLETED',
  COMPLETED_WITH_WARNINGS: 'COMPLETED_WITH_WARNINGS',
  FAILED: 'FAILED',
  FAILED_TIMEOUT: 'FAILED_TIMEOUT',
  CANCELLED: 'CANCELLED'
};

export const TERMINAL_RUN_STATUSES = new Set([
  RUN_STATUSES.COMPLETED,
  RUN_STATUSES.COMPLETED_WITH_WARNINGS,
  RUN_STATUSES.FAILED,
  RUN_STATUSES.FAILED_TIMEOUT,
  RUN_STATUSES.CANCELLED
]);

export const STREAM_LIMITS = {
  'jobs:orchestration': 1000,
  'jobs:calendar_sync': 500,
  'jobs:priority_recompute': 500,
  'jobs:notifications': 500,
  'jobs:dlq': 1000
};

export const STREAMS_BY_KIND = {
  [RUN_KINDS.ASSIGNMENT_BREAKDOWN]: 'jobs:orchestration',
  [RUN_KINDS.SUBTASK_BREAKDOWN]: 'jobs:orchestration',
  [RUN_KINDS.SCHEDULE_REBUILD]: 'jobs:orchestration',
  [RUN_KINDS.SYLLABUS_PARSE]: 'jobs:orchestration',
  [RUN_KINDS.TIMETABLE_EXTRACT]: 'jobs:orchestration'
};

export const RUN_TIMEOUTS_MS = {
  [RUN_KINDS.ASSIGNMENT_BREAKDOWN]: 15 * 60 * 1000,
  [RUN_KINDS.SUBTASK_BREAKDOWN]: 15 * 60 * 1000,
  [RUN_KINDS.SCHEDULE_REBUILD]: 15 * 60 * 1000,
  [RUN_KINDS.SYLLABUS_PARSE]: 15 * 60 * 1000,
  [RUN_KINDS.TIMETABLE_EXTRACT]: 3 * 60 * 1000
};

export const RUN_HEARTBEAT_INTERVAL_MS = 10 * 1000;
export const RUN_LEASE_TTL_MS = 30 * 1000;

export const isTerminalRunStatus = (status) => TERMINAL_RUN_STATUSES.has(status);
