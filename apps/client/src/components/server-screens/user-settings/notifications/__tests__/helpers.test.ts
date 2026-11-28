import { describe, expect, it } from 'bun:test';
import { fromMessageLevel, toMessageLevel } from '../helpers';

describe('message notification level', () => {
  it('reads all messages over mentions, as the notifier does', () => {
    expect(toMessageLevel(true, true)).toBe('all');
    expect(toMessageLevel(true, false)).toBe('all');
    expect(toMessageLevel(false, true)).toBe('mentions');
    expect(toMessageLevel(false, false)).toBe('off');
  });

  it('never stores both flags on', () => {
    expect(fromMessageLevel('all')).toEqual({ all: true, mentions: false });
    expect(fromMessageLevel('mentions')).toEqual({
      all: false,
      mentions: true
    });
    expect(fromMessageLevel('off')).toEqual({ all: false, mentions: false });
  });
});
