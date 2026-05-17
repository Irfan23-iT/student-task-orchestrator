import test from 'node:test';
import assert from 'node:assert/strict';

import { verifyBearerClaims } from '../middleware/authMiddleware.js';

test('verifyBearerClaims converts expired JWT exceptions into missing claims', async () => {
  const result = await verifyBearerClaims({
    auth: {
      getClaims() {
        throw new Error('JWT has expired');
      },
    },
    token: 'expired-token',
    requestId: 'request-1',
  });

  assert.deepEqual(result, { claims: null });
});

test('verifyBearerClaims returns claims for a valid token', async () => {
  const claims = { sub: 'user-1', email: 'student@example.com' };
  const result = await verifyBearerClaims({
    auth: {
      getClaims() {
        return Promise.resolve({
          data: { claims },
          error: null,
        });
      },
    },
    token: 'valid-token',
    requestId: 'request-2',
  });

  assert.deepEqual(result, { claims });
});
