import { getErrorMessage } from '@sharkord/shared';
import { lookup } from 'dns/promises';
import type { IceCandidate } from 'mediasoup/types';
import { isIP } from 'net';
import { logger } from '../logger';

const resolveCandidate = async (
  candidate: IceCandidate
): Promise<IceCandidate[]> => {
  if (isIP(candidate.address)) return [candidate];

  try {
    const addresses = await lookup(candidate.address, { all: true });

    return [
      candidate,
      ...addresses.map(({ address }, index) => ({
        ...candidate,
        ip: address,
        address,
        foundation: `${candidate.foundation}r${index}`,
        priority: candidate.priority - index - 1
      }))
    ];
  } catch (error) {
    logger.warn(
      'Could not resolve the announced address %s: %s',
      candidate.address,
      getErrorMessage(error)
    );

    return [candidate];
  }
};

// an announced address that is a hostname reaches the browser as a hostname candidate.
// chromium resolves it itself, which is what makes split dns work there, but firefox follows
// rfc 8839 and drops it, so it never connects. the hostname candidate stays first and each
// address the server resolves it to follows it, at a lower priority, for firefox to use
const resolveIceCandidates = async (
  candidates: IceCandidate[]
): Promise<IceCandidate[]> => {
  const resolved = await Promise.all(candidates.map(resolveCandidate));

  return resolved.flat();
};

export { resolveIceCandidates };
