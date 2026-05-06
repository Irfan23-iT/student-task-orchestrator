import { createClient } from 'redis';
import { log } from './logger.js';

let redisPromise = null;
let redisClient = null;
let redisClientFactory = (options) => createClient(options);

export const resolveRedisUrl = () => process.env.REDIS_URL || 'redis://127.0.0.1:6379';

export const getRedisConnectionConfig = () => ({
  url: resolveRedisUrl(),
  usingDefaultUrl: !process.env.REDIS_URL
});

export const getRedis = async () => {
  if (!redisPromise) {
    const client = redisClientFactory({
      url: resolveRedisUrl(),
      socket: {
        connectTimeout: Number.parseInt(process.env.REDIS_CONNECT_TIMEOUT_MS || '750', 10),
        reconnectStrategy: false
      }
    });
    redisClient = client;
    client.on('error', (error) => {
      log('error', 'Redis client error', { error });
    });

    redisPromise = client
      .connect()
      .then(() => {
        log('info', 'Redis client connected', { redisUrl: resolveRedisUrl() });
        return client;
      })
      .catch((error) => {
        redisPromise = null;
        redisClient = null;
        throw error;
      });
  }

  return redisPromise;
};

export const closeRedis = async () => {
  const client = redisClient;
  redisPromise = null;
  redisClient = null;

  if (!client) {
    return;
  }

  if (typeof client.quit === 'function' && client.isOpen) {
    await client.quit();
    return;
  }

  if (typeof client.disconnect === 'function') {
    await client.disconnect();
  }
};

export const resetRedisForTests = () => {
  redisPromise = null;
  redisClient = null;
  redisClientFactory = (options) => createClient(options);
};

export const setRedisClientFactoryForTests = (factory) => {
  redisPromise = null;
  redisClientFactory = factory;
};
