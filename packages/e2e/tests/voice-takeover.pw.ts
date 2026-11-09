import { TestId } from '@sharkord/shared';
import { expect, loginAs, test } from './fixtures';

const BANNER_TEXT = /connected at another location/;

// the real join, which needs a browser with a microphone: joining the same call from a second
// tab has to end the first and offer it back there
test('joining from another tab offers the call back to the first', async ({
  browser
}) => {
  const firstContext = await browser.newContext();
  const secondContext = await browser.newContext();

  // a headless browser's microphone request can hang, and the call only needs an audio track
  for (const context of [firstContext, secondContext]) {
    await context.addInitScript(`
      navigator.mediaDevices.getUserMedia = async () => {
        const audio = new AudioContext();
        const destination = audio.createMediaStreamDestination();

        audio.createOscillator().connect(destination);

        return destination.stream;
      };
    `);
  }

  try {
    const first = await firstContext.newPage();
    const second = await secondContext.newPage();

    await loginAs(first, 'testowner', 'password123');
    await loginAs(second, 'testowner', 'password123');

    const voiceChannel = (page: typeof first) =>
      page.getByTestId(TestId.CHANNEL_ITEM).filter({ hasText: /^Voice$/ });

    await voiceChannel(first).click();
    await expect(first.getByText('Voice connected')).toBeVisible({
      timeout: 15_000
    });

    await voiceChannel(second).click();
    await expect(second.getByText('Voice connected')).toBeVisible({
      timeout: 15_000
    });

    await expect(first.getByText(BANNER_TEXT)).toBeVisible();
    await expect(second.getByText(BANNER_TEXT)).toHaveCount(0);

    await first.getByRole('button', { name: 'Reconnect' }).click();

    await expect(first.getByText(BANNER_TEXT)).toHaveCount(0);
    await expect(first.getByText('Voice connected')).toBeVisible({
      timeout: 15_000
    });
    await expect(second.getByText(BANNER_TEXT)).toBeVisible();
  } finally {
    await firstContext.close().catch(() => {});
    await secondContext.close().catch(() => {});
  }
});
