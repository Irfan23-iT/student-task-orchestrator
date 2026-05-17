import { supabase } from '../config/supabase.js';
import { getAccessState } from '../lib/accessState.js';
import { log } from '../lib/logger.js';

const parseBearerToken = (headerValue = '') => {
  const [scheme, token] = String(headerValue).split(' ');
  if (scheme?.toLowerCase() !== 'bearer' || !token) return null;
  return token.trim();
};

export const verifyBearerClaims = async ({ auth, token, requestId }) => {
  try {
    const { data, error } = await auth.getClaims(token);
    const claims = data?.claims;

    if (error || !claims?.sub) {
      log('warn', 'JWT verification failed', {
        requestId,
        error
      });
      return { claims: null };
    }

    return { claims };
  } catch (error) {
    log('warn', 'JWT verification failed', {
      requestId,
      error
    });
    return { claims: null };
  }
};

export const requireAuth = async (req, res, next) => {
  try {
    const token = parseBearerToken(req.headers.authorization);
    if (!token) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { claims } = await verifyBearerClaims({
      auth: supabase.auth,
      token,
      requestId: req.requestId
    });

    if (!claims?.sub) {
      return res.status(401).json({
        error: 'Unauthorized',
        message: 'Token expired or invalid'
      });
    }

    const accessState = await getAccessState(claims.sub);
    if (accessState.disabled || accessState.banned) {
      return res.status(403).json({ error: 'Account access blocked' });
    }

    const revokedAfter = accessState.revokedAfter ? Date.parse(accessState.revokedAfter) : null;
    const issuedAtSeconds = Number(claims.iat || 0);
    if (revokedAfter && issuedAtSeconds > 0 && issuedAtSeconds * 1000 < revokedAfter) {
      return res.status(401).json({ error: 'Session revoked' });
    }

    req.user = {
      id: claims.sub,
      email: claims.email || null,
      claims
    };

    next();
  } catch (error) {
    log('error', 'Auth middleware failure', {
      requestId: req.requestId,
      error
    });
    res.status(500).json({ error: 'Internal server error' });
  }
};
