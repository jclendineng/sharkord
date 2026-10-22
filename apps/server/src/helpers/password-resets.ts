import { ActivityLogType, DisconnectCode, sha256 } from '@sharkord/shared';
import { randomBytes } from 'crypto';
import { and, eq, gt, sql } from 'drizzle-orm';
import { db } from '../db';
import { passwordResets, sessions, users, userTotp } from '../db/schema';
import { enqueueActivityLog } from '../queues/activity-log';
import { disconnectUser } from '../utils/wss';

const PASSWORD_RESET_TTL_MS = 24 * 60 * 60 * 1000;

// a new link replaces any earlier one for the same account, so only the latest works
const createPasswordReset = async (userId: number, createdBy: number) => {
  const token = randomBytes(32).toString('base64url');
  const now = Date.now();
  const expiresAt = now + PASSWORD_RESET_TTL_MS;
  const tokenHash = await sha256(token);

  db.transaction((tx) => {
    tx.delete(passwordResets).where(eq(passwordResets.userId, userId)).run();
    tx.insert(passwordResets)
      .values({ tokenHash, userId, createdBy, expiresAt, createdAt: now })
      .run();
  });

  return { token, expiresAt };
};

// sets the new password and spends the link in one go, signing out every session the account
// had, since whoever forgot the password may not be the only one who knew it. false for a link
// that is unknown, used or expired
const redeemPasswordReset = async (
  token: string,
  newPassword: string
): Promise<boolean> => {
  const tokenHash = await sha256(token);
  const reset = await db
    .select({ userId: passwordResets.userId })
    .from(passwordResets)
    .where(
      and(
        eq(passwordResets.tokenHash, tokenHash),
        gt(passwordResets.expiresAt, Date.now())
      )
    )
    .limit(1)
    .get();

  if (!reset) return false;

  const hashedPassword = (await Bun.password.hash(newPassword)).toString();

  // the link is spent inside the transaction, since hashing takes long enough for a second
  // request with the same link to pass the read above. only the one that deletes it goes on
  const spent = db.transaction((tx) => {
    const spentReset = tx
      .delete(passwordResets)
      .where(
        and(
          eq(passwordResets.tokenHash, tokenHash),
          gt(passwordResets.expiresAt, Date.now())
        )
      )
      .returning({ userId: passwordResets.userId })
      .get();

    if (!spentReset) return false;

    tx.update(users)
      .set({
        password: hashedPassword,
        passwordSet: true,
        tokenVersion: sql`${users.tokenVersion} + 1`
      })
      .where(eq(users.id, reset.userId))
      .run();

    tx.delete(sessions).where(eq(sessions.userId, reset.userId)).run();
    // a moderator vouching for the person is the way back for someone who lost their
    // authenticator and its recovery codes too, so the link turns two-factor off as well
    tx.delete(userTotp).where(eq(userTotp.userId, reset.userId)).run();
    tx.delete(passwordResets)
      .where(eq(passwordResets.userId, reset.userId))
      .run();

    return true;
  });

  if (!spent) return false;

  disconnectUser(
    reset.userId,
    DisconnectCode.KICKED,
    'Your password was reset'
  );

  enqueueActivityLog({
    type: ActivityLogType.USER_UPDATED_PASSWORD,
    userId: reset.userId
  });

  return true;
};

export { createPasswordReset, redeemPasswordReset };
