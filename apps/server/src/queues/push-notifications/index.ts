import { getErrorMessage } from '@sharkord/shared';
import chalk from 'chalk';
import { inArray } from 'drizzle-orm';
import Queue from 'queue';
import { config } from '../../config';
import { db } from '../../db';
import { pushDevices } from '../../db/schema';
import { logger } from '../../logger';
import type { TConnectionInfo } from '../../types';
import { sendApnsNotification, type TApnsResult } from '../../utils/apns';
import { encryptForDevice } from '../../utils/push-encryption';
import { sendRelayNotification } from '../../utils/push-relay';
import { drainQueue } from '../drain';
import {
  buildPushPayload,
  getPushMessage,
  getRecipientDevices
} from './helpers';
import { buildLoginPayload, getLoginNotificationDevices } from './login';

// apple's answers for a token that will never work again, see "handling notification
// responses from apns" in its documentation, and the relay's for a ticket that won't
const DEAD_TOKEN_REASONS = new Set([
  'BadDeviceToken',
  'Unregistered',
  'DeviceTokenNotForTopic',
  'BadTicket',
  'ExpiredTicket',
  'TicketNotForServer'
]);

const pushNotificationsQueue = new Queue({
  concurrency: 2,
  autostart: true,
  timeout: 30_000
});

pushNotificationsQueue.autostart = true;

type TDeliveryDevice = {
  id: number;
  token: string;
  sandbox: boolean;
  relayTicket: string | null;
  encryptionKey: string | null;
};

const isPushEnabled = () => config.push.enabled || !!config.push.relayUrl;

// a device behind the relay gets the payload encrypted to its own key, so the relay and apple
// only ever carry ciphertext. one apns is sent to directly needs this server's own key
const sendToDevice = async (
  device: TDeliveryDevice,
  payload: Record<string, unknown>
): Promise<TApnsResult | undefined> => {
  if (device.relayTicket && device.encryptionKey) {
    if (!config.push.relayUrl) return undefined;

    return sendRelayNotification({
      ticket: device.relayTicket,
      encrypted: await encryptForDevice(device.encryptionKey, payload)
    });
  }

  if (!config.push.enabled) return undefined;

  return sendApnsNotification({
    deviceToken: device.token,
    sandbox: device.sandbox,
    payload
  });
};

// one payload to each device, dropping the ones apple or the relay says will never work again
const deliver = async (
  devices: TDeliveryDevice[],
  payload: Record<string, unknown>
) => {
  const results = await Promise.allSettled(
    devices.map((device) => sendToDevice(device, payload))
  );

  const deadDeviceIds: number[] = [];

  results.forEach((result, index) => {
    if (result.status === 'rejected') {
      logger.warn(
        `${chalk.dim('[Push]')} Could not reach APNs or the relay: %s`,
        getErrorMessage(result.reason)
      );

      return;
    }

    if (!result.value) return;

    const { status, reason } = result.value;

    if (status === 410 || (reason && DEAD_TOKEN_REASONS.has(reason))) {
      deadDeviceIds.push(devices[index]!.id);
    } else if (status !== 200) {
      logger.warn(
        `${chalk.dim('[Push]')} A notification was refused with %d (%s)`,
        status,
        reason ?? 'no reason'
      );
    }
  });

  if (deadDeviceIds.length > 0) {
    await db.delete(pushDevices).where(inArray(pushDevices.id, deadDeviceIds));
  }
};

const sendMessagePushNotifications = async (messageId: number) => {
  const message = await getPushMessage(messageId);

  if (!message) return;

  const devices = await getRecipientDevices(message);

  if (devices.length === 0) return;

  await deliver(devices, await buildPushPayload(message));
};

const sendLoginNotifications = async (
  userId: number,
  sessionId: string,
  info: TConnectionInfo | undefined
) => {
  const devices = await getLoginNotificationDevices(userId, sessionId);

  if (devices.length === 0) return;

  await deliver(devices, await buildLoginPayload(info));
};

const enqueuePushNotification = (messageId: number) => {
  if (!isPushEnabled()) return;

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

// the account's other devices hear that it was signed in to somewhere new
const enqueueLoginNotification = (
  userId: number,
  sessionId: string,
  info: TConnectionInfo | undefined
) => {
  if (!isPushEnabled()) return;

  pushNotificationsQueue.push(async (callback) => {
    try {
      await sendLoginNotifications(userId, sessionId, info);
    } catch (error) {
      logger.error(
        `${chalk.dim('[Push]')} Failed to send the new login notification: %s`,
        getErrorMessage(error)
      );
    }

    callback?.();
  });
};

const drainPushNotificationsQueue = () => drainQueue(pushNotificationsQueue);

export {
  drainPushNotificationsQueue,
  enqueueLoginNotification,
  enqueuePushNotification
};
