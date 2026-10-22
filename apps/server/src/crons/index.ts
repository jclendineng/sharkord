import { CronJob } from 'cron';
import { deleteExpiredMessages } from '../helpers/message-retention';
import { logger } from '../logger';
import { cleanupFiles } from './cleanup-files';
import { moveAfkUsers } from './move-afk-users';
import { sweepStaleUploads } from './sweep-stale-uploads';

enum CRON_TIMES {
  EVERY_15_MINUTES = '*/15 * * * *',
  EVERY_HOUR = '0 * * * *',
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
    CRON_TIMES.EVERY_15_MINUTES,
    sweepStaleUploads,
    null,
    true,
    'Europe/Lisbon',
    null,
    true
  );

  new CronJob(
    CRON_TIMES.EVERY_HOUR,
    deleteExpiredMessages,
    null,
    true,
    'Europe/Lisbon',
    null,
    false
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
