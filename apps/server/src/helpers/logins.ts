import type { TIpInfo } from '@sharkord/shared';
import { ipCache } from '../utils/ip-cache';

const LOOKUP_TIMEOUT_MS = 2000;

const getIpInfo = async (ip: string) => {
  const isLocalIp =
    ip.startsWith('192.168.') || ip.startsWith('::1') || ip === '127.0.0.1';

  const cachedData = ipCache.get(ip);

  if (cachedData) {
    return cachedData;
  }

  const url = isLocalIp
    ? 'https://ipinfo.io/json'
    : `https://ipinfo.io/${ip}/json`;

  // well inside the logins queue's own timeout, which would drop the whole job
  const response = await fetch(url, {
    signal: AbortSignal.timeout(LOOKUP_TIMEOUT_MS)
  });
  const data = (await response.json()) as TIpInfo;

  ipCache.set(ip, data);

  return data;
};

export { getIpInfo };
