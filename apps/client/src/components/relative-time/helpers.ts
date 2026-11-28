import { format, isToday, isYesterday, type Locale } from 'date-fns';
import type { TFunction } from 'i18next';

const ONE_HOUR = 3_600_000;

// the apps' style: today and yesterday by name, anything older as a short date, all with the time
export const getFormattedTime = (
  d: Date,
  dateLocale: Locale,
  t: TFunction
): string => {
  const time = format(d, 'p', { locale: dateLocale });

  if (isToday(d)) {
    return t('dateToday', { time });
  }

  if (isYesterday(d)) {
    return t('dateYesterday', { time });
  }

  return format(d, 'P, p', { locale: dateLocale });
};

// only a time from today or yesterday changes as midnight passes, hourly is soon enough
export const getUpdateInterval = (date: Date): number | null => {
  if (isToday(date) || isYesterday(date)) {
    return ONE_HOUR;
  }

  return null;
};
