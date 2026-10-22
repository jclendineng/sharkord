import chalk from 'chalk';
import { config, SERVER_PRIVATE_IP, SERVER_PUBLIC_IP } from '../config';
import * as serverPaths from '../helpers/paths';
import * as envVars from './env';

// debug output ends up in logs people paste into issues, so anything that reads like a secret
// is left out of the config dump
const SECRET_KEY_PATTERN =
  /secret|password|token|apikey|api_key|privatekey|private_key/i;

const redactSecrets = (key: string, value: unknown) =>
  SECRET_KEY_PATTERN.test(key) && typeof value === 'string' && value.length > 0
    ? '[redacted]'
    : value;

const printDebug = () => {
  if (!config.server.debug) return;

  const message = [
    chalk.dim('────────────────────────────────────────────────────'),
    `${chalk.blue('Bun version:')} ${chalk.bold(String(Bun.version_with_sha))}`,
    `${chalk.blue('Local address:')} ${chalk.bold(String(SERVER_PRIVATE_IP))}`,
    `${chalk.blue('Public address:')} ${chalk.bold(
      String(config.webRtc.announcedAddress || SERVER_PUBLIC_IP)
    )}`,
    `${chalk.blue('Server paths:')} ${chalk.bold(
      String(
        Object.entries(serverPaths)
          .map(([key, value]) => `\n  ${key}: ${value}`)
          .join('')
      )
    )}`,
    `${chalk.blue('Config:')} ${chalk.bold(
      String(JSON.stringify(config, redactSecrets, 2))
    )}`,
    `${chalk.blue('Environment Variables:')} ${chalk.bold(
      String(
        Object.entries(envVars)
          .map(([key, value]) => `\n  ${key}: ${value}`)
          .join('')
      )
    )}`
  ].join('\n');

  console.log('%s', message);
  console.log(
    chalk.dim('────────────────────────────────────────────────────')
  );
  console.log(
    chalk.white.bold('Debug mode is enabled. This may affect performance.')
  );
};

export { printDebug };
