import { supabase } from '../config/supabase.js';
import { getRedis } from './redis.js';
import { log } from './logger.js';

const CACHE_TTL_SECONDS = 60;

const defaultState = {
  disabled: false,
  banned: false,
  revokedAfter: null
};

export const getAccessState = async (userId) => {
  const cacheKey = `access-state:${userId}`;
  let redis = null;

  try {
    redis = await getRedis();
    const cached = await redis.get(cacheKey);
    if (cached) {
      return JSON.parse(cached);
    }
  } catch (error) {
    log('warn', 'Access-state cache unavailable; querying database directly', {
      userId,
      error
    });
  }

  try {
    const { data, error } = await supabase
      .from('users')
      .select('access_disabled, access_banned, access_revoked_after')
      .eq('id', userId)
      .maybeSingle();

    if (error) throw error;

    const nextState = {
      disabled: Boolean(data?.access_disabled),
      banned: Boolean(data?.access_banned),
      revokedAfter: data?.access_revoked_after || null
    };

    if (redis) {
      try {
        await redis.set(cacheKey, JSON.stringify(nextState), {
          EX: CACHE_TTL_SECONDS
        });
      } catch (cacheError) {
        log('warn', 'Access-state cache write failed', {
          userId,
          error: cacheError
        });
      }
    }

    return nextState;
  } catch (error) {
    log('warn', 'Access-state lookup fell back to defaults', {
      userId,
      error
    });
    return defaultState;
  }
};
