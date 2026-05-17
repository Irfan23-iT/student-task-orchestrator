import 'dotenv/config';

import { getSystemReadinessSnapshot } from '../lib/systemReadiness.js';
import { closeRedis } from '../lib/redis.js';

const main = async () => {
  try {
    const report = await getSystemReadinessSnapshot();
    console.log(JSON.stringify(report, null, 2));

    if (report.status === 'ready') {
      process.exitCode = 0;
      return;
    }

    if (report.status === 'degraded') {
      process.exitCode = 2;
      return;
    }

    process.exitCode = 1;
  } finally {
    await closeRedis();
  }
};

main().catch((error) => {
  console.error(
    JSON.stringify({
      status: 'error',
      message: error.message || String(error)
    })
  );
  process.exitCode = 1;
});
