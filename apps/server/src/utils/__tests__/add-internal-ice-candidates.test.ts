import { describe, expect, test } from 'bun:test';
import type { IceCandidate } from 'mediasoup/types';
import { addInternalIceCandidates } from '../add-internal-ice-candidates';

const PUBLIC_IP = '203.0.113.7';
const INTERNAL_IP = '192.168.1.10';

const udpCandidate: IceCandidate = {
  foundation: 'udpcandidate',
  priority: 1076302079,
  ip: PUBLIC_IP,
  address: PUBLIC_IP,
  protocol: 'udp',
  port: 40000,
  type: 'host'
};

const tcpCandidate: IceCandidate = {
  foundation: 'tcpcandidate',
  priority: 1076276479,
  ip: PUBLIC_IP,
  address: PUBLIC_IP,
  protocol: 'tcp',
  port: 40000,
  type: 'host',
  tcpType: 'passive'
};

describe('addInternalIceCandidates', () => {
  test('should return the candidates untouched when no internal address is set', () => {
    const candidates = [udpCandidate, tcpCandidate];

    expect(addInternalIceCandidates(candidates, undefined)).toBe(candidates);
  });

  test('should keep every public candidate so remote clients can still connect', () => {
    const result = addInternalIceCandidates(
      [udpCandidate, tcpCandidate],
      INTERNAL_IP
    );

    expect(result).toContainEqual(udpCandidate);
    expect(result).toContainEqual(tcpCandidate);
    expect(result).toHaveLength(4);
  });

  test('should add an internal copy of each candidate on the same port and protocol', () => {
    const result = addInternalIceCandidates(
      [udpCandidate, tcpCandidate],
      INTERNAL_IP
    );

    const internal = result.filter(({ address }) => address === INTERNAL_IP);

    expect(internal).toHaveLength(2);

    for (const candidate of internal) {
      expect(candidate.ip).toBe(INTERNAL_IP);
      expect(candidate.port).toBe(40000);
      expect(candidate.type).toBe('host');
    }

    expect(internal.map(({ protocol }) => protocol).sort()).toEqual([
      'tcp',
      'udp'
    ]);
    expect(internal.find(({ protocol }) => protocol === 'tcp')?.tcpType).toBe(
      'passive'
    );
  });

  // two candidates with one foundation are treated as the same network path by ice
  test('should give the internal candidates their own foundations', () => {
    const result = addInternalIceCandidates(
      [udpCandidate, tcpCandidate],
      INTERNAL_IP
    );

    const foundations = result.map(({ foundation }) => foundation);

    expect(new Set(foundations).size).toBe(foundations.length);

    for (const foundation of foundations) {
      expect(foundation).toMatch(/^[a-zA-Z0-9+/]{1,32}$/);
    }
  });

  test('should prefer the internal path, without ranking udp below tcp', () => {
    const result = addInternalIceCandidates(
      [udpCandidate, tcpCandidate],
      INTERNAL_IP
    );

    const priorityOf = (address: string, protocol: string) => {
      const candidate = result.find(
        (c) => c.address === address && c.protocol === protocol
      );

      return candidate ? candidate.priority : 0;
    };

    expect(priorityOf(INTERNAL_IP, 'udp')).toBeGreaterThan(
      priorityOf(PUBLIC_IP, 'udp')
    );
    expect(priorityOf(INTERNAL_IP, 'tcp')).toBeGreaterThan(
      priorityOf(PUBLIC_IP, 'tcp')
    );
    expect(priorityOf(PUBLIC_IP, 'udp')).toBeGreaterThan(
      priorityOf(INTERNAL_IP, 'tcp')
    );
  });

  test('should only copy candidates of the internal address family', () => {
    const ipv6Candidate: IceCandidate = {
      ...udpCandidate,
      foundation: 'udpv6candidate',
      ip: '2001:db8::7',
      address: '2001:db8::7'
    };

    const result = addInternalIceCandidates(
      [udpCandidate, ipv6Candidate],
      INTERNAL_IP
    );

    const internal = result.filter(({ address }) => address === INTERNAL_IP);

    expect(internal.map(({ foundation }) => foundation)).toEqual([
      'udpcandidateinternal'
    ]);
  });

  test('should add nothing when the internal address is the announced one', () => {
    const candidates = [udpCandidate, tcpCandidate];

    expect(addInternalIceCandidates(candidates, PUBLIC_IP)).toEqual(candidates);
  });
});
