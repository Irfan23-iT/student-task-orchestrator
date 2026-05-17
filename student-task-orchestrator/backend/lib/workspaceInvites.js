import { randomBytes } from 'node:crypto';

const INVITE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const DEFAULT_INVITE_CODE_LENGTH = 8;
const MAX_INVITE_CODE_ATTEMPTS = 12;

export const normalizeInviteCode = (value) => `${value || ''}`.trim().toUpperCase();

export const createInviteCode = (length = DEFAULT_INVITE_CODE_LENGTH) => {
  const bytes = randomBytes(length);
  let output = '';

  for (let index = 0; index < length; index += 1) {
    output += INVITE_ALPHABET[bytes[index] % INVITE_ALPHABET.length];
  }

  return output;
};

export const createUniqueInviteCode = async (lookupFn, options = {}) => {
  const length = Number(options.length || DEFAULT_INVITE_CODE_LENGTH);
  const maxAttempts = Number(options.maxAttempts || MAX_INVITE_CODE_ATTEMPTS);
  const createCode = options.createCode || createInviteCode;

  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    const code = createCode(length);
    const exists = await lookupFn(code);
    if (!exists) {
      return code;
    }
  }

  const error = new Error('Unable to allocate a unique workspace invite code.');
  error.statusCode = 503;
  throw error;
};
