import { describe, expect, test } from 'bun:test';
import type { IceCandidate } from 'mediasoup/types';
import { resolveIceCandidates } from '../resolve-ice-candidates';

const candidate = (address: string): IceCandidate => ({
  foundation: 'udpcandidate',
  priority: 1076302079,
  ip: address,
  address,
  protocol: 'udp',
  port: 40000,
  type: 'host'
});

describe('resolveIceCandidates', () => {
  test('should leave an ip candidate as it is', async () => {
    const resolved = await resolveIceCandidates([candidate('203.0.113.7')]);

    expect(resolved).toEqual([candidate('203.0.113.7')]);
  });

  test('should keep a hostname candidate first and add its addresses after it', async () => {
    const resolved = await resolveIceCandidates([candidate('localhost')]);

    expect(resolved[0]).toEqual(candidate('localhost'));
    expect(resolved.length).toBeGreaterThan(1);

    resolved.slice(1).forEach((extra) => {
      expect(['127.0.0.1', '::1']).toContain(extra.address);
      expect(extra.ip).toBe(extra.address);
      expect(extra.port).toBe(40000);
      expect(extra.priority).toBeLessThan(resolved[0]!.priority);
      expect(extra.foundation).not.toBe(resolved[0]!.foundation);
    });
  });

  test('should keep only the hostname candidate when it does not resolve', async () => {
    const resolved = await resolveIceCandidates([
      candidate('no-such-host.invalid')
    ]);

    expect(resolved).toEqual([candidate('no-such-host.invalid')]);
  });
});
