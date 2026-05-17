import { getErrorTrackingCapabilities } from './errorTracking.js';
import { getLogMetricsSnapshot } from './logger.js';
import { getRedis, getRedisConnectionConfig } from './redis.js';
import { STREAM_LIMITS } from './runStatus.js';

const createEmptyCounters = () => ({
  total: 0,
  byMethod: {},
  byStatusFamily: {
    '2xx': 0,
    '3xx': 0,
    '4xx': 0,
    '5xx': 0,
    other: 0
  }
});

const createQueueCounters = () => ({
  published: {},
  failed: {}
});

const httpCounters = createEmptyCounters();
const queueCounters = createQueueCounters();

const increment = (bucket, key) => {
  bucket[key] = Number(bucket[key] || 0) + 1;
};

const toStatusFamily = (statusCode) => {
  const code = Number(statusCode || 0);
  if (code >= 200 && code < 300) return '2xx';
  if (code >= 300 && code < 400) return '3xx';
  if (code >= 400 && code < 500) return '4xx';
  if (code >= 500 && code < 600) return '5xx';
  return 'other';
};

const cloneObject = (value = {}) => JSON.parse(JSON.stringify(value));

const readStreamLength = async (redis, stream) => {
  try {
    const length = await redis.sendCommand(['XLEN', stream]);
    return Number(length || 0);
  } catch (error) {
    const message = `${error?.message || ''}`.toLowerCase();
    if (message.includes('no such key')) {
      return 0;
    }

    throw error;
  }
};

export const recordHttpRequest = ({ method, statusCode }) => {
  const normalizedMethod = `${method || 'UNKNOWN'}`.toUpperCase();

  httpCounters.total += 1;
  increment(httpCounters.byMethod, normalizedMethod);
  increment(httpCounters.byStatusFamily, toStatusFamily(statusCode));
};

export const recordQueuePublish = ({ stream, success }) => {
  const bucket = success ? queueCounters.published : queueCounters.failed;
  increment(bucket, stream || 'unknown');
};

export const resetOperationalMetricsForTests = () => {
  Object.assign(httpCounters, createEmptyCounters());
  Object.assign(queueCounters, createQueueCounters());
};

export const buildOperationsMetricsSnapshot = ({
  redisReachable = false,
  streamDepths = {},
  redisError = '',
  redisUrl = getRedisConnectionConfig().url,
  redisUsingDefaultUrl = getRedisConnectionConfig().usingDefaultUrl
} = {}) => ({
  generatedAt: new Date().toISOString(),
  redis: {
    reachable: Boolean(redisReachable),
    url: redisUrl,
    usingDefaultUrl: Boolean(redisUsingDefaultUrl),
    error: redisError || ''
  },
  http: cloneObject(httpCounters),
  queue: {
    published: cloneObject(queueCounters.published),
    failed: cloneObject(queueCounters.failed),
    streams: Object.entries(STREAM_LIMITS).map(([name, maxLen]) => ({
      name,
      maxLen,
      depth: Number(streamDepths[name] || 0)
    }))
  },
  dlq: {
    name: 'jobs:dlq',
    depth: Number(streamDepths['jobs:dlq'] || 0)
  },
  logs: getLogMetricsSnapshot(),
  errorTracking: getErrorTrackingCapabilities()
});

export const getOperationsMetricsSnapshot = async () => {
  const redisConfig = getRedisConnectionConfig();

  try {
    const redis = await getRedis();
    const streamEntries = await Promise.all(
      Object.keys(STREAM_LIMITS).map(async (stream) => [stream, await readStreamLength(redis, stream)])
    );

    return buildOperationsMetricsSnapshot({
      redisReachable: true,
      streamDepths: Object.fromEntries(streamEntries),
      redisUrl: redisConfig.url,
      redisUsingDefaultUrl: redisConfig.usingDefaultUrl
    });
  } catch (error) {
    return buildOperationsMetricsSnapshot({
      redisReachable: false,
      redisError: error.message || String(error),
      redisUrl: redisConfig.url,
      redisUsingDefaultUrl: redisConfig.usingDefaultUrl
    });
  }
};
