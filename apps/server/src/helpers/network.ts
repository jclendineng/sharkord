import ipaddr from 'ipaddr.js';
import { isIP } from 'net';
import os from 'os';

const getPrivateIp = async () => {
  const interfaces = os.networkInterfaces();
  const addresses = Object.values(interfaces)
    .flat()
    .filter((iface) => iface?.family === 'IPv4' && !iface.internal)
    .map((iface) => iface?.address);

  return addresses[0];
};

// every lookup is a third party call on the boot path, so it must be bounded
const PUBLIC_IP_TIMEOUT_MS = 3000;

const fetchWithTimeout = async (url: string): Promise<Response> =>
  fetch(url, { signal: AbortSignal.timeout(PUBLIC_IP_TIMEOUT_MS) });

const getPublicIpFromIpify = async (): Promise<string | undefined> => {
  try {
    const response = await fetchWithTimeout(
      'https://api.ipify.org?format=json'
    );
    const data = (await response.json()) as {
      ip: string;
    };

    return data.ip;
  } catch {
    return undefined;
  }
};

// fallback since it can return ipv6 sometimes
const getPublicIpFromIfconfig = async (): Promise<string | undefined> => {
  try {
    const response = await fetchWithTimeout('https://ifconfig.me/ip');
    const ip = (await response.text()).trim();

    return ip;
  } catch {
    return undefined;
  }
};

const getPublicIpFromIcanhazip = async (): Promise<string | undefined> => {
  try {
    const response = await fetchWithTimeout('https://ipv4.icanhazip.com');
    const ip = (await response.text()).trim();

    return ip;
  } catch {
    return undefined;
  }
};

const getPublicIp = async () => {
  let ip = await getPublicIpFromIcanhazip();

  if (!ip) {
    ip = await getPublicIpFromIpify();
  }

  if (!ip) {
    ip = await getPublicIpFromIfconfig();
  }

  if (!ip) {
    // logger imports config, which imports this file, so console keeps the
    // boot path free of a circular import
    console.warn(
      'Could not determine the public IP address from any provider. Set webRtc.announcedAddress in config.ini if voice does not work.'
    );
  }

  return ip;
};

// webRtc.announcedAddressV6 turns the ipv6 listener on. it has to be a literal ipv6 address:
// a hostname would also resolve to ipv4 addresses the ipv6 listener can't take. anything else
// leaves ipv6 off with a warning, rather than failing the config and losing the rest of it
const getAnnouncedAddressV6 = (announcedAddressV6: string): string => {
  const address = announcedAddressV6.trim();

  if (!address || isIP(address) === 6) return address;

  // logger imports config, which imports this file, see getPublicIp
  console.warn(
    `webRtc.announcedAddressV6 "${address}" is not an IPv6 address, IPv6 voice is off.`
  );

  return '';
};

// the single answer to "is this a routable public address". an allowlist of one range
// rather than a blocklist, so anything ipaddr does not call unicast (carrierGradeNat,
// reserved, benchmarking and friends) is treated as not public. an unparseable address is
// not public either, which is what makes isPrivateIP below fail closed
const isPublicIp = (ip: string): boolean => {
  try {
    const parsed = ipaddr.parse(ip);

    if (parsed.kind() === 'ipv6') {
      const v6 = parsed as ipaddr.IPv6;

      if (v6.isIPv4MappedAddress())
        return v6.toIPv4Address().range() === 'unicast';
    }

    return parsed.range() === 'unicast';
  } catch {
    return false;
  }
};

const isPrivateIP = (ip: string): boolean => !isPublicIp(ip);

export {
  getAnnouncedAddressV6,
  getPrivateIp,
  getPublicIp,
  isPrivateIP,
  isPublicIp
};
