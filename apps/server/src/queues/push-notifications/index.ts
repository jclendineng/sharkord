import { getErrorMessage } from '@sharkord/shared';
import chalk from 'chalk';
import { inArray } from 'drizzle-orm';
import Queue from 'queue';
import { config } from '../../config';
import { db } from '../../db';
import { pushDevices } from '../../db/schema';
import { logger } from '../../logger';
import { sendApnsNotification } from '../../utils/apns';
import { drainQueue } from '../drain';
import {
  buildPushPayload,
  getPushMessage,
  getRecipientDevices
} from './helpers';

// apple's answers for a token that will never work again, see "handling notification
// responses from apns" in its documentation
const DEAD_TOKEN_REASONS = new Set([
  'BadDeviceToken',
  'Unregistered',
  'DeviceTokenNotForTopic'
]);

const pushNotificationsQueue = new Queue({
  concurrency: 2,
  autostart: true,
  timeout: 30_000
});

pushNotificationsQueue.autostart = true;

const sendMessagePushNotifications = async (messageId: number) => {
  const message = await getPushMessage(messageId);

  if (!message) return;

  const devices = await getRecipientDevices(message);

  if (devices.length === 0) return;

  const payload = await buildPushPayload(message);

  const results = await Promise.allSettled(
    devices.map((device) =>
      sendApnsNotification({
        deviceToken: device.token,
        sandbox: device.sandbox,
        payload
      })
    )
  );

  const deadDeviceIds: number[] = [];

  results.forEach((result, index) => {
    if (result.status === 'rejected') {
      logger.warn(
        `${chalk.dim('[Push]')} Could not reach APNs: %s`,
        getErrorMessage(result.reason)
      );

      return;
    }

    const { status, reason } = result.value;

    if (status === 410 || (reason && DEAD_TOKEN_REASONS.has(reason))) {
      deadDeviceIds.push(devices[index]!.id);
    } else if (status !== 200) {
      logger.warn(
        `${chalk.dim('[Push]')} APNs refused a notification with %d (%s)`,
        status,
        reason ?? 'no reason'
      );
    }
  });

  if (deadDeviceIds.length > 0) {
    await db.delete(pushDevices).where(inArray(pushDevices.id, deadDeviceIds));
  }
};

const enqueuePushNotification = (messageId: number) => {
  if (!config.push.enabled) return;

  pushNotificationsQueue.push(async (callback) => {
    try {
      await sendMessagePushNotifications(messageId);
    } catch (error) {
      logger.error(
        `${chalk.dim('[Push]')} Failed to send notifications for message %d: %s`,
        messageId,
        getErrorMessage(error)
      );
    }

    callback?.();
  });
};

const drainPushNotificationsQueue = () => drainQueue(pushNotificationsQueue);

export { drainPushNotificationsQueue, enqueuePushNotification };
