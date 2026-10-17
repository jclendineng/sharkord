import { expect, test } from '@playwright/test';
import { TestId } from '@sharkord/shared';

test.describe('Auto Login', () => {
  test('should display the auto-login switch on the connect screen', async ({
    page
  }) => {
    await page.goto('/');

    const autoLoginSwitch = page.getByTestId(TestId.CONNECT_AUTO_LOGIN_SWITCH);
    await expect(autoLoginSwitch).toBeVisible();
    await expect(autoLoginSwitch).toContainText('Login automatically');
  });

  test('should have the auto-login switch checked by default', async ({
    page
  }) => {
    await page.goto('/');

    const switchButton = page
      .getByTestId(TestId.CONNECT_AUTO_LOGIN_SWITCH)
      .locator('button[role="switch"]');
    await expect(switchButton).toHaveAttribute('data-state', 'checked');
  });

  test('should toggle the auto-login switch', async ({ page }) => {
    await page.goto('/');

    const autoLoginSwitch = page.getByTestId(TestId.CONNECT_AUTO_LOGIN_SWITCH);
    const switchButton = autoLoginSwitch.locator('button[role="switch"]');

    await autoLoginSwitch.click();
    await expect(switchButton).toHaveAttribute('data-state', 'unchecked');

    await autoLoginSwitch.click();
    await expect(switchButton).toHaveAttribute('data-state', 'checked');
  });

  test('should restore the auto-login switch state from localStorage', async ({
    page
  }) => {
    await page.goto('/');

    await page.evaluate(() => {
      localStorage.setItem('sharkord-keep-signed-in', 'true');
    });

    await page.reload();

    const switchButton = page
      .getByTestId(TestId.CONNECT_AUTO_LOGIN_SWITCH)
      .locator('button[role="switch"]');
    await expect(switchButton).toHaveAttribute('data-state', 'checked');
  });

  test('should show the connect screen when auto-login is enabled but no token is saved', async ({
    page
  }) => {
    await page.goto('/');

    await page.evaluate(() => {
      localStorage.setItem('sharkord-keep-signed-in', 'true');
      localStorage.removeItem('sharkord-auto-login-token');
    });

    await page.reload();

    const connectButton = page.getByTestId(TestId.CONNECT_BUTTON);
    await expect(connectButton).toBeVisible();
  });

  test('should show the connect screen when auto-login is disabled even with a saved token', async ({
    page
  }) => {
    await page.goto('/');

    await page.evaluate(() => {
      localStorage.setItem('sharkord-keep-signed-in', 'false');
      localStorage.setItem('sharkord-auto-login-token', 'some-token');
    });

    await page.reload();

    const connectButton = page.getByTestId(TestId.CONNECT_BUTTON);
    await expect(connectButton).toBeVisible();
  });

  test('should attempt auto-connect when auto-login is enabled and token is saved', async ({
    page
  }) => {
    await page.goto('/');

    await page.evaluate(() => {
      localStorage.setItem('sharkord-keep-signed-in', 'true');
      localStorage.setItem('sharkord-auto-login-token', 'invalid-token');
    });

    await page.reload();

    // the token is invalid so it should fall back to the connect screen
    const connectButton = page.getByTestId(TestId.CONNECT_BUTTON);
    await expect(connectButton).toBeVisible({ timeout: 10_000 });

    // the refused token is forgotten, but the preference stays for the next sign in
    const autoLoginEnabled = await page.evaluate(() =>
      localStorage.getItem('sharkord-keep-signed-in')
    );
    expect(autoLoginEnabled).toBe('true');

    const savedToken = await page.evaluate(() =>
      localStorage.getItem('sharkord-auto-login-token')
    );
    expect(savedToken).toBeNull();
  });
});
