import type { TServerInfo } from '@sharkord/shared';
import http from 'http';
import { config } from '../config';
import { getSettings } from '../db/queries/server';
import { getOidcServerInfo } from '../helpers/oidc/settings';
import { getPushRelayKey } from '../utils/push-relay-key';

const infoRouteHandler = async (
  req: http.IncomingMessage,
  res: http.ServerResponse
) => {
  const [settings, pushRelayKey] = await Promise.all([
    getSettings(),
    config.push.relayUrl ? getPushRelayKey() : undefined
  ]);

  const info: TServerInfo = {
    serverId: settings.serverId,
    name: settings.name,
    description: settings.description,
    logo: settings.logo,
    allowNewUsers: settings.allowNewUsers,
    // public so a report can be sent before signing in, and without an account at all
    reportEmail: settings.reportEmail,
    pushEnabled: config.push.enabled,
    pushRelayKey: pushRelayKey?.publicKey ?? null,
    ...getOidcServerInfo()
  };

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(info));
};

export { infoRouteHandler };
