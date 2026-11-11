import type { Page } from '@playwright/test';
import { TestId } from '@sharkord/shared';
import { expect, loginAs, test } from './fixtures';
import { confirmDialog } from './helpers/dialogs';

// the spec builds and removes its own category, so it touches nothing the rest of the suite
// reads and survives a retry. a seeded one would be gone on the second attempt
// channel names cap at 27 characters, so the run marker is short enough to fit inside one
const RUN_ID = Date.now().toString().slice(-8);

const CATEGORY = `Doomed Category ${RUN_ID}`;
const CHANNEL = `doomed-channel-${RUN_ID}`;

const categoryItem = (page: Page, name: string) =>
  page.getByTestId(TestId.CATEGORY_ITEM).filter({ hasText: name });

const submitDialog = async (page: Page, value: string) => {
  // waiting for the dialog rather than for its textbox: a dropdown item clicked mid animation
  // can be missed entirely, and then the failure points at the input instead of the click
  const dialog = page.getByRole('dialog');

  await expect(dialog).toBeVisible();
  await dialog.getByRole('textbox').fill(value);
  await page.keyboard.press('Enter');
  await expect(dialog).toBeHidden();
};

const createCategoryWithChannel = async (page: Page) => {
  await page.getByTestId(TestId.SERVER_MENU_TRIGGER).click();

  const addCategory = page.getByTestId(TestId.SERVER_MENU_ADD_CATEGORY);

  await expect(addCategory).toBeVisible();
  await addCategory.click();
  await submitDialog(page, CATEGORY);

  await expect(categoryItem(page, CATEGORY)).toBeVisible();

  // a click on the + while the sidebar is still settling around the new category is lost, which
  // only shows on slow ci runners. clicked again only while the dialog is shut, since a click
  // on an open one would be intercepted by its overlay
  const addChannel = categoryItem(page, CATEGORY).getByTestId(
    TestId.CATEGORY_ADD_CHANNEL
  );
  const dialog = page.getByRole('dialog');

  await expect(async () => {
    if (!(await dialog.isVisible())) {
      await addChannel.click();
    }

    await expect(dialog).toBeVisible({ timeout: 2_000 });
  }).toPass({ timeout: 15_000 });

  await submitDialog(page, CHANNEL);

  // a rejected name leaves the dialog open and the category empty, which would otherwise
  // surface as the watcher never seeing a category that was never worth seeing
  await expect(page.getByText(CHANNEL)).toBeVisible();
};

const deleteCategory = async (page: Page, name: string) => {
  // the context menu wraps the name, not the whole row: the row's padding and its + button
  // are outside the trigger
  await categoryItem(page, name).getByText(name).click({ button: 'right' });
  await page.getByTestId(TestId.CATEGORY_MENU_DELETE).click();
  await confirmDialog(page);
};

// a failure partway leaves the category behind, and connect.pw.ts, which counts the seeded
// ones, then fails on every attempt even after this spec's own retry passes. waits for it to
// go, or closing the page could drop the delete before it is sent
const removeLeftoverCategory = async (page: Page) => {
  const isLeftBehind = (await categoryItem(page, CATEGORY).count()) > 0;

  if (!isLeftBehind) return;

  await deleteCategory(page, CATEGORY);
  await expect(categoryItem(page, CATEGORY)).toHaveCount(0);
};

// categories.test.ts covers the server side: the channels are announced and any call in them
// is dropped. what only a browser shows is the other client's sidebar reacting to those
// events, which is the half that would silently need a reload if a subscription were missed
test('deleting a category removes it and its channels from every client', async ({
  browser
}) => {
  const ownerContext = await browser.newContext();
  const watcherContext = await browser.newContext();
  const owner = await ownerContext.newPage();

  try {
    const watcher = await watcherContext.newPage();

    await loginAs(owner, 'testowner', 'password123');
    await loginAs(watcher, 'testuser', 'password123');

    await createCategoryWithChannel(owner);

    // the watcher learns about both through a subscription, which under a full parallel run
    // can take longer than the default expect timeout allows
    await expect(categoryItem(watcher, CATEGORY)).toBeVisible({
      timeout: 15_000
    });
    await expect(watcher.getByText(CHANNEL)).toBeVisible({ timeout: 15_000 });

    await deleteCategory(owner, CATEGORY);

    for (const page of [owner, watcher]) {
      await expect(categoryItem(page, CATEGORY)).toHaveCount(0, {
        timeout: 15_000
      });
      await expect(page.getByText(CHANNEL)).toHaveCount(0, { timeout: 15_000 });
    }
  } finally {
    await removeLeftoverCategory(owner).catch(() => {
      // the page itself is broken, the next seed starts clean
    });

    await ownerContext.close().catch(() => {});
    await watcherContext.close().catch(() => {});
  }
});
