import type { TServerInfo } from '@sharkord/shared';
import http from 'http';
import { config } from '../config';
import { getSettings } from '../db/queries/server';
import { getOidcServerInfo } from '../helpers/oidc/settings';

const infoRouteHandler = async (
  req: http.IncomingMessage,
  res: http.ServerResponse
) => {
  const settings = await getSettings();

  const info: TServerInfo = {
    serverId: settings.serverId,
    name: settings.name,
    description: settings.description,
    logo: settings.logo,
    allowNewUsers: settings.allowNewUsers,
    pushEnabled: config.push.enabled,
    ...getOidcServerInfo()
  };

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(info));
};

export { infoRouteHandler };
