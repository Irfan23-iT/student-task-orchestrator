import { getRedis } from './redis.js';
import { recordQueuePublish } from './operationsMetrics.js';
import { STREAM_LIMITS } from './runStatus.js';

const toRedisFields = (payload) =>
  Object.entries(payload).flatMap(([key, value]) => [key, typeof value === 'string' ? value : JSON.stringify(value)]);

export const publishStreamJob = async ({ stream, payload }) => {
  const redis = await getRedis();
  const maxLen = STREAM_LIMITS[stream] || 1000;

  try {
    const entryId = await redis.sendCommand([
      'XADD',
      stream,
      'MAXLEN',
      '~',
      String(maxLen),
      '*',
      ...toRedisFields(payload)
    ]);

    recordQueuePublish({ stream, success: true });
    return entryId;
  } catch (error) {
    recordQueuePublish({ stream, success: false });
    throw error;
  }
};
