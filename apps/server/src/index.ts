// these two imports NEED to be at the very top in this order
// keep the "---------" because it forces prettier to not mess with the order, I can't turn this off here for some reason, need to check later
import { ensureServerDirs } from './helpers/ensure-server-dirs';
await ensureServerDirs();
// ----------------------------------------
import { loadEmbeds } from './helpers/embeds';
await loadEmbeds();
// ----------------------------------------
import { IS_DEVELOPMENT, IS_PRODUCTION, SERVER_VERSION } from './utils/env';
// ----------------------------------------
import { ActivityLogType } from '@sharkord/shared';
import chalk from 'chalk';
import { config, SERVER_PRIVATE_IP } from './config';
import { loadCrons } from './crons';
import { loadDb } from './db';
import { syncConfigFile, watchConfigFile } from './helpers/config-file-sync';
import { getHost } from './helpers/get-host';
import { renameStoredFiles } from './helpers/rename-stored-files';
import { pluginManager } from './plugins';
import { enqueueActivityLog } from './queues/activity-log';
import { initVoiceRuntimes } from './runtimes';
import { createServers } from './utils/create-servers';
import { loadMediasoup } from './utils/mediasoup';
import { printDebug } from './utils/print-debug';

await loadDb();
await renameStoredFiles();
await syncConfigFile();
watchConfigFile();
await pluginManager.init();
await createServers();
await loadMediasoup();
await initVoiceRuntimes();
await loadCrons();

const LOOPBACK_HOSTS = ['127.0.0.1', '::1', 'localhost'];

const host = getHost(
  config.server.host,
  (IS_PRODUCTION && SERVER_PRIVATE_IP) || 'localhost'
);
const url = `http://${host}:${config.server.port}/`;

const message = [
  chalk.green.bold('SHARKORD') + ' ' + chalk.white.bold(`v${SERVER_VERSION}`),
  chalk.dim('────────────────────────────────────────────────────'),
  `${chalk.yellow('Port:')} ${chalk.bold(String(config.server.port))}`,
  `${chalk.yellow('Interface:')} ${chalk.underline.cyan(url)}`
].join('\n');

console.log('%s', message);

// rate limiting is off in development, so a source run server reachable from other machines
// has no brake on login or token guessing
if (IS_DEVELOPMENT && !LOOPBACK_HOSTS.includes(config.server.host)) {
  console.log(
    '\n%s\n',
    chalk.redBright.bold(
      'This is a development build listening on the network with rate limiting turned off. Set server.host to 127.0.0.1 in config.ini, or run a production build, before exposing it.'
    )
  );
}

printDebug();

enqueueActivityLog({
  type: ActivityLogType.SERVER_STARTED
});
