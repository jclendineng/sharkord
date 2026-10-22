import {
  MARKETPLACE_REGISTRY_URL,
  parseMarketplaceRegistry,
  type TMarketplacePluginVersion
} from '@sharkord/shared';
import { invariant } from '../utils/invariant';
import { readBodyWithLimit } from '../utils/read-body-with-limit';

const REGISTRY_TIMEOUT_MS = 10_000;
const REGISTRY_MAX_BYTES = 5 * 1024 * 1024;

const fetchMarketplaceVersion = async (
  pluginId: string,
  version: string
): Promise<TMarketplacePluginVersion> => {
  const response = await fetch(MARKETPLACE_REGISTRY_URL, {
    signal: AbortSignal.timeout(REGISTRY_TIMEOUT_MS)
  });

  invariant(response.ok, 'Failed to fetch marketplace registry');

  const chunks: Uint8Array[] = [];

  await readBodyWithLimit(response, {
    maxBytes: REGISTRY_MAX_BYTES,
    tooLargeMessage: 'The marketplace registry is larger than expected',
    onChunk: (chunk) => chunks.push(chunk)
  });

  const entries = parseMarketplaceRegistry(
    JSON.parse(Buffer.concat(chunks).toString('utf-8'))
  );
  const entry = entries.find((e) => e.plugin.id === pluginId);

  invariant(entry, `Plugin '${pluginId}' not found in marketplace`);

  const versionData = entry.versions.find((v) => v.version === version);

  invariant(
    versionData,
    `Version '${version}' not found for plugin '${pluginId}'`
  );

  return versionData;
};

export { fetchMarketplaceVersion };
