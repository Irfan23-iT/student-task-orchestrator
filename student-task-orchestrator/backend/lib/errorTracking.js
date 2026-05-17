const resolveErrorTrackingWebhookUrl = () =>
  `${process.env.ERROR_TRACKING_WEBHOOK_URL || ''}`.trim();

export const getErrorTrackingCapabilities = () => {
  const webhookUrl = resolveErrorTrackingWebhookUrl();

  return {
    configured: Boolean(webhookUrl),
    provider: webhookUrl ? 'webhook' : 'none'
  };
};

export const reportErrorEvent = async (event = {}) => {
  const webhookUrl = resolveErrorTrackingWebhookUrl();
  if (!webhookUrl || typeof fetch !== 'function') {
    return false;
  }

  try {
    const response = await fetch(webhookUrl, {
      method: 'POST',
      headers: {
        'content-type': 'application/json'
      },
      body: JSON.stringify({
        ts: new Date().toISOString(),
        ...event
      })
    });

    return response.ok;
  } catch {
    return false;
  }
};
