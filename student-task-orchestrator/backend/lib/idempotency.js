import { log } from './logger.js';

const PENDING_TTL_SECONDS = 5;
const ACCEPTED_TTL_SECONDS = 60 * 60 * 24;
const HEARTBEAT_INTERVAL_MS = 1000;
const MAX_PENDING_LIFETIME_MS = 15000;

const encodeValue = (state, payloadHash, subject) => `${state}|${payloadHash}|${subject}`;

const parseStoredValue = (value) => {
  if (!value) return null;

  const [state, payloadHash, subject] = String(value).split('|');
  if (!state || !payloadHash || !subject) return null;

  return { state, payloadHash, subject };
};

export const buildIdempotencyKey = (userId, clientKey) => `idem:${userId}:${clientKey}`;

export const acquireIdempotencyLock = async ({
  redis,
  userId,
  clientKey,
  payloadHash,
  requestId
}) => {
  const key = buildIdempotencyKey(userId, clientKey);
  const pendingValue = encodeValue('pending', payloadHash, requestId);
  const acquired = await redis.set(key, pendingValue, {
    NX: true,
    EX: PENDING_TTL_SECONDS
  });

  if (acquired === 'OK') {
    return { state: 'acquired', key, value: pendingValue };
  }

  const existing = parseStoredValue(await redis.get(key));
  if (!existing) {
    return { state: 'conflict', key, reason: 'unknown' };
  }

  if (existing.payloadHash !== payloadHash) {
    return { state: 'conflict', key, reason: 'payload_mismatch' };
  }

  if (existing.state === 'pending') {
    return { state: 'pending', key };
  }

  return { state: 'accepted', key, runId: existing.subject };
};

export const startPendingHeartbeat = ({ redis, key, payloadHash, requestId }) => {
  const expectedValue = encodeValue('pending', payloadHash, requestId);
  const startedAt = Date.now();
  let stopped = false;

  const timer = setInterval(async () => {
    if (stopped) return;

    if (Date.now() - startedAt > MAX_PENDING_LIFETIME_MS) {
      clearInterval(timer);
      return;
    }

    try {
      const currentValue = await redis.get(key);
      if (currentValue !== expectedValue) {
        clearInterval(timer);
        return;
      }

      await redis.set(key, expectedValue, {
        XX: true,
        EX: PENDING_TTL_SECONDS
      });
    } catch (error) {
      log('warn', 'Idempotency heartbeat failed', {
        key,
        requestId,
        error
      });
    }
  }, HEARTBEAT_INTERVAL_MS);

  return () => {
    stopped = true;
    clearInterval(timer);
  };
};

export const finalizeAcceptedLock = async ({
  redis,
  key,
  payloadHash,
  runId
}) => {
  const acceptedValue = encodeValue('accepted', payloadHash, runId);
  const updated = await redis.set(key, acceptedValue, {
    XX: true,
    EX: ACCEPTED_TTL_SECONDS
  });

  if (updated !== 'OK') {
    await redis.set(key, acceptedValue, {
      EX: ACCEPTED_TTL_SECONDS
    });
  }
};
