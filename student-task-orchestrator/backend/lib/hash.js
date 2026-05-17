import crypto from 'node:crypto';

export const sha256 = (value) => {
  const normalized =
    typeof value === 'string' ? value : JSON.stringify(value ?? {}, Object.keys(value ?? {}).sort());

  return crypto.createHash('sha256').update(normalized).digest('hex');
};
