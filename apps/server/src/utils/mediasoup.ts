import { getErrorMessage } from '@sharkord/shared';
import mediasoup from 'mediasoup';
import { config, SERVER_PUBLIC_IP } from '../config.js';
import { getAnnouncedAddressV6 } from '../helpers/network.js';
import { MEDIASOUP_BINARY_PATH } from '../helpers/paths.js';
import { logger } from '../logger.js';
import {
  patchSpawnForMediasoup,
  restoreSpawn
} from './bun-mediasoup-workaround.js';
import { IS_PRODUCTION } from './env.js';
import { getWebRtcListenInfos } from './webrtc-listen-infos.js';

let mediaSoupWorker: mediasoup.types.Worker<mediasoup.types.AppData>;
let webRtcServer: mediasoup.types.WebRtcServer<mediasoup.types.AppData>;
let webRtcServerListenInfo: { ip: string; announcedAddress?: string };

const loadMediasoup = async () => {
  const port = +config.webRtc.port;

  const workerConfig: mediasoup.types.WorkerSettings = {
    logLevel: 'debug',
    workerBin: MEDIASOUP_BINARY_PATH
  };

  logger.debug(
    `Loading mediasoup worker with config ${JSON.stringify(workerConfig, null, 2)}`
  );

  // On Bun/Windows, extra stdio pipes (fd 3/4) are broken (oven-sh/bun#11044).
  // This patches child_process.spawn to use Bun.spawn() for the mediasoup
  // worker, which correctly supports extra stdio pipe handles.
  try {
    patchSpawnForMediasoup();
    mediaSoupWorker = await mediasoup.createWorker(workerConfig);
  } catch (error) {
    logger.error('Failed to load mediasoup worker: %s', getErrorMessage(error));
  } finally {
    restoreSpawn();
  }

  mediaSoupWorker.on('died', (error) => {
    logger.error('Mediasoup worker died: %s', getErrorMessage(error));

    setTimeout(() => process.exit(0), 2000);
  });

  logger.debug('Mediasoup worker loaded');

  if (IS_PRODUCTION) {
    const { listenInfos, ip, announcedAddress } = getWebRtcListenInfos({
      listenIp: config.webRtc.listenIp,
      announcedAddress: config.webRtc.announcedAddress || SERVER_PUBLIC_IP,
      announcedAddressV6: getAnnouncedAddressV6(
        config.webRtc.announcedAddressV6
      ),
      port
    });

    webRtcServer = await mediaSoupWorker.createWebRtcServer({ listenInfos });

    webRtcServerListenInfo = { ip, announcedAddress };

    logger.debug(
      `WebRtcServer created on ${listenInfos
        .map(
          (info) =>
            `${info.protocol} ${info.ip}:${port} (${info.announcedAddress})`
        )
        .join(', ')}`
    );
  } else {
    webRtcServer = await mediaSoupWorker.createWebRtcServer({
      listenInfos: [
        { protocol: 'udp', ip: '127.0.0.1', port },
        { protocol: 'tcp', ip: '127.0.0.1', port }
      ]
    });

    webRtcServerListenInfo = { ip: '127.0.0.1' };

    logger.debug(`WebRtcServer created on 127.0.0.1:${port} (dev mode)`);
  }
};

export { loadMediasoup, mediaSoupWorker, webRtcServer, webRtcServerListenInfo };
