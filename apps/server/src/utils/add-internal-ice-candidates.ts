import type { IceCandidate } from 'mediasoup/types';
import { isIP } from 'net';

// a copy of every candidate on webRtc.internalAnnouncedAddress, for self hosted servers whose
// lan clients cannot reach the public address (no nat loopback, split dns). it ranks just
// above the public one it copies, so a client that reaches both takes the internal path, and
// udp still ranks above tcp. a hostname is left for resolveIceCandidates, like the announced one
const addInternalIceCandidates = (
  candidates: IceCandidate[],
  internalAddress: string | undefined
): IceCandidate[] => {
  if (!internalAddress) return candidates;

  const internalFamily = isIP(internalAddress);

  // with announcedAddressV6 on, the ipv6 listener's candidates must not be copied onto an
  // ipv4 internal address or the other way round. a hostname matches either
  const isSameFamily = (address: string) => {
    const family = isIP(address);

    return family === 0 || internalFamily === 0 || family === internalFamily;
  };

  const internalCandidates = candidates
    .filter(
      ({ address }) => address !== internalAddress && isSameFamily(address)
    )
    .map((candidate) => ({
      ...candidate,
      foundation: `${candidate.foundation}internal`,
      priority: candidate.priority + 1,
      ip: internalAddress,
      address: internalAddress
    }));

  return [...internalCandidates, ...candidates];
};

export { addInternalIceCandidates };
