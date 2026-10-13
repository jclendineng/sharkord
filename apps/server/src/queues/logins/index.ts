import { getErrorMessage, type TIpInfo } from '@sharkord/shared';
import Queue from 'queue';
import { db } from '../../db';
import { logins } from '../../db/schema';
import { getIpInfo } from '../../helpers/logins';
import { logger } from '../../logger';
import type { TConnectionInfo } from '../../types';
import { drainQueue } from '../drain';

const loginsQueue = new Queue({
  concurrency: 1,
  autostart: true,
  timeout: 3000
});

loginsQueue.autostart = true;

const enqueueLogin = (userId: number, info: TConnectionInfo | undefined) => {
  loginsQueue.push(async (callback) => {
    if (!info) {
      logger.warn('No connection info provided for login of user %d', userId);
      callback?.();
      return;
    }
    const { ip, ...rest } = info;
    let ipInfo: TIpInfo | undefined;

    // the location is a nice to have from a third party service. a blocked or offline lookup
    // must not lose the login itself, which also decides whether the welcome dialog shows
    if (ip) {
      try {
        ipInfo = await getIpInfo(ip);
      } catch (error) {
        logger.warn(
          'Could not look up the location of %s: %s',
          ip,
          getErrorMessage(error)
        );
      }
    }

    await db
      .insert(logins)
      .values({
        userId,
        ip,
        ...rest,
        ...ipInfo,
        createdAt: Date.now()
      })
      .returning()
      .get();

    callback?.();
  });
};

const drainLoginsQueue = () => drainQueue(loginsQueue);

export { drainLoginsQueue, enqueueLogin };
