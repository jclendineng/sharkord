import type { TServerInfo } from '@sharkord/shared';
import http from 'http';
import { getSettings } from '../db/queries/server';
import { getOidcServerInfo } from '../helpers/oidc/settings';
import { getPushRelayKey } from '../utils/push-relay-key';

const infoRouteHandler = async (
  req: http.IncomingMessage,
  res: http.ServerResponse
) => {
  const settings = await getSettings();
  // without the key the app never asks the relay for a ticket, so push is off
  const pushRelayKey = settings.pushRelayEnabled
    ? await getPushRelayKey()
    : undefined;

  const info: TServerInfo = {
    serverId: settings.serverId,
    name: settings.name,
    description: settings.description,
    logo: settings.logo,
    allowNewUsers: settings.allowNewUsers,
    // public so a report can be sent before signing in, and without an account at all
    reportEmail: settings.reportEmail,
    pushRelayKey: pushRelayKey?.publicKey ?? null,
    ...getOidcServerInfo()
  };

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(info));
};

export { infoRouteHandler };
