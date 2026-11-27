import type { TransportListenInfo } from 'mediasoup/types';
import { isIP } from 'net';

type TWebRtcListenOptions = {
  listenIp: string;
  announcedAddress: string | undefined;
  announcedAddressV6: string;
  port: number;
};

type TWebRtcListen = {
  listenInfos: TransportListenInfo[];
  // the ipv4 side, which plain transports and the debug output use
  ip: string;
  announcedAddress: string | undefined;
};

const listenPair = (
  ip: string,
  announcedAddress: string | undefined,
  port: number,
  flags?: TransportListenInfo['flags']
): TransportListenInfo[] => [
  { protocol: 'udp', ip, announcedAddress, port, ...(flags && { flags }) },
  { protocol: 'tcp', ip, announcedAddress, port, ...(flags && { flags }) }
];

// announcedAddressV6 adds an ipv6 only listener on the same port, announcing that address,
// next to the ipv4 one. off when empty, which keeps listenIp exactly as it was. a listenIp
// of :: already takes ipv6 and would hold the port the ipv6 listener needs, so with the
// option on the ipv4 listener moves to 0.0.0.0, and an ipv6 listenIp is used for the ipv6 side
const getWebRtcListenInfos = ({
  listenIp,
  announcedAddress,
  announcedAddressV6,
  port
}: TWebRtcListenOptions): TWebRtcListen => {
  if (!announcedAddressV6) {
    return {
      listenInfos: listenPair(listenIp, announcedAddress, port),
      ip: listenIp,
      announcedAddress
    };
  }

  const isListenIpV6 = isIP(listenIp) === 6;
  const ipv4 = isListenIpV6 ? '0.0.0.0' : listenIp;
  const ipv6 = isListenIpV6 ? listenIp : '::';

  return {
    listenInfos: [
      ...listenPair(ipv4, announcedAddress, port),
      ...listenPair(ipv6, announcedAddressV6, port, { ipv6Only: true })
    ],
    ip: ipv4,
    announcedAddress
  };
};

export { getWebRtcListenInfos };
