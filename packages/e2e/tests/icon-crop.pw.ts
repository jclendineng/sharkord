import { TestId } from '@sharkord/shared';
import { expect, loginAs, test } from './fixtures';

const OUTPUT_SIDE = 512;

// left half red, right half blue, so where the crop landed can be read off the result
const twoColourPicture = `(() => {
  const canvas = document.createElement('canvas');

  canvas.width = 1200;
  canvas.height = 600;

  const context = canvas.getContext('2d');

  context.fillStyle = '#ff0000';
  context.fillRect(0, 0, 600, 600);
  context.fillStyle = '#0000ff';
  context.fillRect(600, 0, 600, 600);

  return canvas.toDataURL('image/png').split(',')[1];
})()`;

const readPreview = `(() => {
  const image = document.querySelector('img[src^="blob:"]');
  const canvas = document.createElement('canvas');

  canvas.width = image.naturalWidth;
  canvas.height = image.naturalHeight;

  const context = canvas.getContext('2d');

  context.drawImage(image, 0, 0);

  const [red, , blue] = context.getImageData(256, 256, 1, 1).data;

  return { width: image.naturalWidth, height: image.naturalHeight, red, blue };
})()`;

test('a new server icon is framed to a square and saved small', async ({
  page
}) => {
  await loginAs(page, 'testowner', 'password123');

  await page.getByTestId(TestId.SERVER_MENU_TRIGGER).click();
  await page.getByTestId(TestId.SERVER_MENU_SERVER_SETTINGS).click();

  const base64 = await page.evaluate<string>(twoColourPicture);
  const chooser = page.waitForEvent('filechooser');

  await page.locator('.group.cursor-pointer').first().click();

  await (
    await chooser
  ).setFiles({
    name: 'wide.png',
    mimeType: 'image/png',
    buffer: Buffer.from(base64, 'base64')
  });

  const dialog = page.getByRole('dialog');

  await expect(dialog.getByText('Move and Scale')).toBeVisible();

  // dragged as far right as it goes, so the square sits over the picture's left half
  const area = dialog.locator('.cursor-move');
  const box = await area.boundingBox();

  expect(box).not.toBeNull();

  const centre = { x: box!.x + box!.width / 2, y: box!.y + box!.height / 2 };

  await page.mouse.move(centre.x, centre.y);
  await page.mouse.down();
  await page.mouse.move(centre.x + 400, centre.y, { steps: 5 });
  await page.mouse.up();

  await dialog.getByRole('button', { name: 'Use' }).click();
  await expect(dialog).toBeHidden();
  await expect(page.locator('img[src^="blob:"]')).toBeVisible();

  const preview = await page.evaluate<{
    width: number;
    height: number;
    red: number;
    blue: number;
  }>(readPreview);

  expect(preview.width).toBe(OUTPUT_SIDE);
  expect(preview.height).toBe(OUTPUT_SIDE);
  expect(preview.red).toBeGreaterThan(200);
  expect(preview.blue).toBeLessThan(50);
});
