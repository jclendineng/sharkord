import { describe, expect, it } from 'bun:test';
import { enUS } from 'date-fns/locale';
import type { TFunction } from 'i18next';
import { getFormattedTime, getUpdateInterval } from '../helpers';

// the key and its time, so the test sees which form was picked without loading translations
const t = ((key: string, values: { time: string }) =>
  `${key} ${values.time}`) as unknown as TFunction;

const at = (daysAgo: number) => {
  const date = new Date();

  date.setDate(date.getDate() - daysAgo);
  date.setHours(9, 5, 0, 0);

  return date;
};

describe('message times', () => {
  it('names today and yesterday with the time', () => {
    expect(getFormattedTime(at(0), enUS, t)).toBe('dateToday 9:05 AM');
    expect(getFormattedTime(at(1), enUS, t)).toBe('dateYesterday 9:05 AM');
  });

  it('gives anything older a short date and the time', () => {
    const date = new Date(2026, 0, 2, 13, 45);

    expect(getFormattedTime(date, enUS, t)).toBe('01/02/2026, 1:45 PM');
  });

  it('only keeps today and yesterday ticking over midnight', () => {
    expect(getUpdateInterval(at(0))).toBe(3_600_000);
    expect(getUpdateInterval(at(1))).toBe(3_600_000);
    expect(getUpdateInterval(at(3))).toBeNull();
  });
});
