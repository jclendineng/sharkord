import { sha256 } from '@sharkord/shared';
import { randomUUIDv7 } from 'bun';
import chalk from 'chalk';
import { eq } from 'drizzle-orm';
import { db } from './index';
import { settings } from './schema';

// development builds used to seed the literal token `dev`, which is also the jwt signing key,
// so a database created that way is replaced once with a random token. every session signed
// with the old key stops working, which is the point
const rotateDevSecretToken = async () => {
  const devTokenHash = await sha256('dev');
  const row = await db
    .select({ secretToken: settings.secretToken })
    .from(settings)
    .limit(1)
    .get();

  if (!row || row.secretToken !== devTokenHash) return;

  const newToken = randomUUIDv7();

  await db
    .update(settings)
    .set({ secretToken: await sha256(newToken) })
    .where(eq(settings.secretToken, devTokenHash));

  const notice = [
    chalk.redBright.bold('🚨🚨 I M P O R T A N T 🚨🚨'),
    chalk.dim('────────────────────────────────────────────────────'),
    chalk.whiteBright(
      'This server was using the insecure development access token "dev" and it has been replaced.'
    ),
    chalk.whiteBright(
      'Everyone has been signed out. Save the new access token below, it will not be shown again.'
    ),
    chalk.yellowBright('────────────────────────────────────────────────────'),
    chalk.bold.greenBright(newToken),
    chalk.yellowBright('────────────────────────────────────────────────────')
  ].join('\n');

  console.log('\n%s\n', notice);
};

export { rotateDevSecretToken };
