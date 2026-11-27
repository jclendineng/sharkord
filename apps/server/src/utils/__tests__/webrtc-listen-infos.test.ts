import { describe, expect, test } from 'bun:test';
import { getWebRtcListenInfos } from '../webrtc-listen-infos';

const PORT = 40000;
const PUBLIC_IP = '203.0.113.7';
const PUBLIC_IPV6 = '2001:db8::7';

const listenersOf = (listen: ReturnType<typeof getWebRtcListenInfos>) =>
  listen.listenInfos.map(({ protocol, ip, announcedAddress, flags }) => ({
    protocol,
    ip,
    announcedAddress,
    ipv6Only: !!flags?.ipv6Only
  }));

describe('getWebRtcListenInfos', () => {
  test('should keep the single listener as it was when ipv6 is off', () => {
    const listen = getWebRtcListenInfos({
      listenIp: '::',
      announcedAddress: PUBLIC_IP,
      announcedAddressV6: '',
      port: PORT
    });

    expect(listenersOf(listen)).toEqual([
      {
        protocol: 'udp',
        ip: '::',
        announcedAddress: PUBLIC_IP,
        ipv6Only: false
      },
      {
        protocol: 'tcp',
        ip: '::',
        announcedAddress: PUBLIC_IP,
        ipv6Only: false
      }
    ]);
    expect(listen.ip).toBe('::');
  });

  test('should add an ipv6 only listener announcing the ipv6 address', () => {
    const listen = getWebRtcListenInfos({
      listenIp: '0.0.0.0',
      announcedAddress: PUBLIC_IP,
      announcedAddressV6: PUBLIC_IPV6,
      port: PORT
    });

    expect(listenersOf(listen)).toEqual([
      {
        protocol: 'udp',
        ip: '0.0.0.0',
        announcedAddress: PUBLIC_IP,
        ipv6Only: false
      },
      {
        protocol: 'tcp',
        ip: '0.0.0.0',
        announcedAddress: PUBLIC_IP,
        ipv6Only: false
      },
      {
        protocol: 'udp',
        ip: '::',
        announcedAddress: PUBLIC_IPV6,
        ipv6Only: true
      },
      {
        protocol: 'tcp',
        ip: '::',
        announcedAddress: PUBLIC_IPV6,
        ipv6Only: true
      }
    ]);
  });

  // a dual stack :: listener would already hold the ipv6 side of the port
  test('should never put two listeners that take ipv6 on the same port', () => {
    const listen = getWebRtcListenInfos({
      listenIp: '::',
      announcedAddress: PUBLIC_IP,
      announcedAddressV6: PUBLIC_IPV6,
      port: PORT
    });

    const takingIpv6 = listen.listenInfos.filter(
      ({ ip, flags }) => ip.includes(':') && !flags?.ipv6Only
    );

    expect(takingIpv6).toEqual([]);
    expect(listen.ip).toBe('0.0.0.0');
  });

  test('should listen for ipv6 on a specific ipv6 listen ip', () => {
    const listen = getWebRtcListenInfos({
      listenIp: '2001:db8::1',
      announcedAddress: PUBLIC_IP,
      announcedAddressV6: PUBLIC_IPV6,
      port: PORT
    });

    const ipv6Listeners = listen.listenInfos.filter(
      ({ flags }) => flags?.ipv6Only
    );

    expect(ipv6Listeners.map(({ ip }) => ip)).toEqual([
      '2001:db8::1',
      '2001:db8::1'
    ]);
  });
});
