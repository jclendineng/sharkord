import { CronJob } from 'cron';
import { logger } from '../logger';
import { cleanupFiles } from './cleanup-files';
import { moveAfkUsers } from './move-afk-users';

enum CRON_TIMES {
  EVERY_15_MINUTES = '*/15 * * * *',
  EVERY_30_SECONDS = '*/30 * * * * *'
}

const loadCrons = () => {
  logger.debug('Loading crons...');

  new CronJob(
    CRON_TIMES.EVERY_15_MINUTES,
    cleanupFiles,
    null,
    true,
    'Europe/Lisbon',
    null,
    true
  );

  new CronJob(
    CRON_TIMES.EVERY_30_SECONDS,
    moveAfkUsers,
    null,
    true,
    'Europe/Lisbon',
    null,
    false
  );
};

export { loadCrons };
