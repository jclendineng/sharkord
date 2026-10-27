import { describe, expect, test } from 'bun:test';
import { createFakeSocket, initTest } from '../../__tests__/helpers';
import { config } from '../../config';

type TCaller = Awaited<ReturnType<typeof initTest>>['caller'];

// the limit is checked before the handler, so calls about ids that do not exist still use it
// up and each one fails fast
const MISSING_ID = 999_999;

const expectRateLimited = async (
  limit: number,
  call: (caller: TCaller) => Promise<unknown>
) => {
  const { caller } = await initTest();

  for (let i = 0; i < limit; i++) {
    await call(caller).catch((error: Error) => {
      expect(error.message).not.toContain('Too many requests');
    });
  }

  await expect(call(caller)).rejects.toThrow(
    'Too many requests. Please try again shortly.'
  );
};

describe('spam prone routes', () => {
  const { messageAction, pluginManage } = config.rateLimiters;

  test('should rate limit pin toggles', async () => {
    await expectRateLimited(messageAction.maxRequests, (caller) =>
      caller.messages.togglePin({ messageId: MISSING_ID })
    );
  });

  test('should rate limit ending polls', async () => {
    await expectRateLimited(messageAction.maxRequests, (caller) =>
      caller.polls.end({ messageId: MISSING_ID })
    );
  });

  test('should rate limit file deletes', async () => {
    await expectRateLimited(messageAction.maxRequests, (caller) =>
      caller.files.delete({ fileId: MISSING_ID })
    );
  });

  test('should rate limit message deletes on a budget of their own', async () => {
    const { caller } = await initTest();
    const { deleteMessage } = config.rateLimiters;

    for (let i = 0; i < deleteMessage.maxRequests; i++) {
      await caller.messages
        .delete({ messageId: MISSING_ID })
        .catch((error: Error) => {
          expect(error.message).not.toContain('Too many requests');
        });
    }

    await expect(
      caller.messages.delete({ messageId: MISSING_ID })
    ).rejects.toThrow('Too many requests. Please try again shortly.');

    // sending is counted apart, so clearing out messages leaves it free
    const messageId = await caller.messages.send({
      channelId: 1,
      content: '<p>still sending</p>',
      files: []
    });

    expect(messageId).toBeGreaterThan(0);
  });

  test('should rate limit plugin toggles', async () => {
    await expectRateLimited(pluginManage.maxRequests, (caller) =>
      caller.plugins.toggle({ pluginId: 'missing-plugin', enabled: true })
    );
  });

  test('should rate limit plugin setting updates', async () => {
    await expectRateLimited(pluginManage.maxRequests, (caller) =>
      caller.plugins.updateSetting({
        pluginId: 'missing-plugin',
        key: 'key',
        value: 'value'
      })
    );
  });
});

describe('subscriptions per socket', () => {
  test('should cap how many subscriptions one socket keeps open', async () => {
    const { caller } = await initTest(1, { socket: createFakeSocket() });
    const subscriptions: { unsubscribe: () => void }[] = [];

    try {
      // a subscription counts while it is subscribed, which is what a real client does
      for (let i = 0; i < 200; i++) {
        const source = await caller.voice.onJoin();

        subscriptions.push(source.subscribe({}));
      }

      await expect(caller.voice.onJoin()).rejects.toThrow(
        'Too many open subscriptions on this connection.'
      );

      subscriptions.pop()!.unsubscribe();

      const source = await caller.voice.onJoin();

      subscriptions.push(source.subscribe({}));
    } finally {
      subscriptions.forEach((subscription) => subscription.unsubscribe());
    }
  });
});
