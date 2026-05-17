import crypto from 'node:crypto';

export const attachRequestContext = (req, res, next) => {
  const requestId = req.headers['x-request-id']?.toString().trim() || crypto.randomUUID();

  req.requestId = requestId;
  res.setHeader('x-request-id', requestId);

  next();
};
