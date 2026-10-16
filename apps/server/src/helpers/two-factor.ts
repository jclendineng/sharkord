import { sha256 } from '@sharkord/shared';
import { randomBytes } from 'crypto';
import { eq } from 'drizzle-orm';
import { db } from '../db';
import { getSettings } from '../db/queries/server';
import { userTotp, users } from '../db/schema';
import { invariant } from '../utils/invariant';
import { generateTotpSecret, getTotpUri, matchTotpStep } from '../utils/totp';

const RECOVERY_CODE_COUNT = 8;

type TSecondFactorResult = 'not-required' | 'ok' | 'missing' | 'invalid';

const normalizeCode = (code: string) =>
  code.replace(/[\s-]/g, '').toLowerCase();

const getTotpRow = (userId: number) =>
  db.select().from(userTotp).where(eq(userTotp.userId, userId)).limit(1).get();

const isTwoFactorEnabled = async (userId: number) => {
  const row = await getTotpRow(userId);

  return !!row?.enabledAt;
};

// a fresh secret each time, replacing a setup that was started and never finished
const startTwoFactorSetup = async (userId: number) => {
  const [existing, user, settings] = await Promise.all([
    getTotpRow(userId),
    db
      .select({ identity: users.identity, passwordSet: users.passwordSet })
      .from(users)
      .where(eq(users.id, userId))
      .get(),
    getSettings()
  ]);

  invariant(!existing?.enabledAt, {
    code: 'BAD_REQUEST',
    message: 'Two-factor authentication is already on.'
  });

  invariant(user, { code: 'NOT_FOUND', message: 'User not found.' });

  // it guards the password sign in, an sso account signs in at its provider instead
  invariant(user.passwordSet, {
    code: 'BAD_REQUEST',
    message:
      'This account signs in through an identity provider, turn on two-factor authentication there.'
  });

  const secret = generateTotpSecret();

  await db
    .insert(userTotp)
    .values({ userId, secret, createdAt: Date.now() })
    .onConflictDoUpdate({
      target: userTotp.userId,
      set: {
        secret,
        lastStep: 0,
        recoveryCodeHashes: [],
        createdAt: Date.now()
      }
    });

  return { secret, uri: getTotpUri(settings.name, user.identity, secret) };
};

const makeRecoveryCodes = () =>
  Array.from({ length: RECOVERY_CODE_COUNT }, () => {
    const code = randomBytes(5).toString('hex');

    return `${code.slice(0, 5)}-${code.slice(5)}`;
  });

// the first code proves the app holds the secret. the recovery codes are only ever shown here
const confirmTwoFactorSetup = async (userId: number, code: string) => {
  const row = await getTotpRow(userId);

  invariant(row && !row.enabledAt, {
    code: 'BAD_REQUEST',
    message: 'Start the setup first.'
  });

  const step = matchTotpStep(row.secret, normalizeCode(code), row.lastStep);

  invariant(step !== null, {
    code: 'BAD_REQUEST',
    message: "That code isn't right. Check the time on your device."
  });

  const recoveryCodes = makeRecoveryCodes();
  const recoveryCodeHashes = await Promise.all(
    recoveryCodes.map((recoveryCode) => sha256(normalizeCode(recoveryCode)))
  );

  await db
    .update(userTotp)
    .set({ lastStep: step, recoveryCodeHashes, enabledAt: Date.now() })
    .where(eq(userTotp.userId, userId));

  return recoveryCodes;
};

// an authenticator code or a recovery code, the recovery code spent once used
const checkSecondFactor = async (
  userId: number,
  code: string | undefined
): Promise<TSecondFactorResult> => {
  const row = await getTotpRow(userId);

  if (!row?.enabledAt) return 'not-required';
  if (!code) return 'missing';

  const normalized = normalizeCode(code);
  const step = matchTotpStep(row.secret, normalized, row.lastStep);

  if (step !== null) {
    await db
      .update(userTotp)
      .set({ lastStep: step })
      .where(eq(userTotp.userId, userId));

    return 'ok';
  }

  const hash = await sha256(normalized);

  if (!row.recoveryCodeHashes.includes(hash)) return 'invalid';

  await db
    .update(userTotp)
    .set({
      recoveryCodeHashes: row.recoveryCodeHashes.filter(
        (stored) => stored !== hash
      )
    })
    .where(eq(userTotp.userId, userId));

  return 'ok';
};

// turning it off takes a current code too, so a session left open cannot remove it
const disableTwoFactor = async (userId: number, code: string) => {
  const result = await checkSecondFactor(userId, code);

  invariant(result !== 'not-required', {
    code: 'BAD_REQUEST',
    message: 'Two-factor authentication is not on.'
  });

  invariant(result === 'ok', {
    code: 'BAD_REQUEST',
    message: "That code isn't right."
  });

  await db.delete(userTotp).where(eq(userTotp.userId, userId));
};

export {
  checkSecondFactor,
  confirmTwoFactorSetup,
  disableTwoFactor,
  isTwoFactorEnabled,
  startTwoFactorSetup
};
