import { describe, expect, test } from 'bun:test';
import { getTotpCode, getTotpStep, matchTotpStep } from '../totp';

// rfc 6238 appendix b, the sha1 secret "12345678901234567890" in base32, cut to six digits
const RFC_SECRET = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

describe('totp', () => {
  test('should match the rfc 6238 test vectors', () => {
    expect(getTotpCode(RFC_SECRET, Math.floor(59 / 30))).toBe('287082');
    expect(getTotpCode(RFC_SECRET, Math.floor(1111111109 / 30))).toBe('081804');
    expect(getTotpCode(RFC_SECRET, Math.floor(1234567890 / 30))).toBe('005924');
  });

  test('should accept the current code once and the neighbouring steps', () => {
    const step = getTotpStep();

    expect(matchTotpStep(RFC_SECRET, getTotpCode(RFC_SECRET, step), 0)).toBe(
      step
    );
    expect(
      matchTotpStep(RFC_SECRET, getTotpCode(RFC_SECRET, step - 1), 0)
    ).toBe(step - 1);
    expect(
      matchTotpStep(RFC_SECRET, getTotpCode(RFC_SECRET, step), step)
    ).toBeNull();
    expect(
      matchTotpStep(RFC_SECRET, getTotpCode(RFC_SECRET, step - 5), 0)
    ).toBeNull();
  });
});
