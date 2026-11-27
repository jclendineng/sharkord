import type { IceCandidate } from 'mediasoup/types';

// a copy of every candidate on webRtc.internalAnnouncedAddress, for self hosted servers whose
// lan clients cannot reach the public address (no nat loopback, split dns). it ranks just
// above the public one it copies, so a client that reaches both takes the internal path, and
// udp still ranks above tcp. a hostname is left for resolveIceCandidates, like the announced one
const addInternalIceCandidates = (
  candidates: IceCandidate[],
  internalAddress: string | undefined
): IceCandidate[] => {
  if (!internalAddress) return candidates;

  const internalCandidates = candidates
    .filter(({ address }) => address !== internalAddress)
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
