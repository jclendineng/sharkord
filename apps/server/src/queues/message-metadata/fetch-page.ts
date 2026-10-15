import dns from 'dns';
import { isIP } from 'net';
import { isPrivateIP } from '../../helpers/network';

const MAX_REDIRECTS = 5;
const FETCH_TIMEOUT_MS = 5000;

type TPage = {
  url: string;
  headers: Record<string, string>;
  data: string;
};

// every address the host resolves to has to be allowed, or one of them could be the private one
const resolveHost = async (
  hostname: string,
  isBlockedAddress: (address: string) => boolean
) => {
  const bare = hostname.replace(/^\[|\]$/g, '');
  let addresses = [bare];

  if (!isIP(bare)) {
    const entries = await dns.promises.lookup(bare, { all: true });

    addresses = entries.map((entry) => entry.address);
  }

  if (addresses.length === 0 || addresses.some(isBlockedAddress)) {
    return undefined;
  }

  return { isPrivate: addresses.some((address) => isPrivateIP(address)) };
};

// fetched here rather than by link-preview-js, which refuses every private address and every host
// without a tld by itself, so a server allowed to preview its own network never could. each
// redirect is checked again, a public page must not be able to bounce the server inward
const fetchPage = async (
  url: string,
  isBlockedAddress: (address: string) => boolean
): Promise<TPage | undefined> => {
  let current = url;

  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    const parsed = new URL(current);

    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return undefined;
    }

    const host = await resolveHost(parsed.hostname, isBlockedAddress);

    if (!host) {
      return undefined;
    }

    const response = await fetch(current, {
      redirect: 'manual',
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      headers: {
        'user-agent': 'Mozilla/5.0 (compatible; Sharkord link preview)',
        accept: 'text/html,application/xhtml+xml,*/*;q=0.8'
      },
      // routers, nas boxes and the like on a home network serve self signed certificates
      tls: host.isPrivate ? { rejectUnauthorized: false } : undefined
    });

    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get('location');

      if (!location) {
        return undefined;
      }

      current = new URL(location, current).toString();

      continue;
    }

    const headers: Record<string, string> = {};

    response.headers.forEach((value, key) => {
      headers[key] = value;
    });

    // anything but a page is described by its content type alone, so a big file is never read
    const contentType = headers['content-type'] ?? '';
    const isPage = contentType.includes('html');
    let data = '';

    if (isPage) {
      data = await response.text();
    } else {
      await response.body?.cancel();
    }

    return { url: current, headers, data };
  }

  return undefined;
};

export { fetchPage };
