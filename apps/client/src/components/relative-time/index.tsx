import { useDateLocale } from '@/hooks/use-date-locale';
import { format, isToday, isYesterday, type Locale } from 'date-fns';
import type { TFunction } from 'i18next';
import { memo, useEffect, useMemo, useState, type ReactNode } from 'react';
import { useTranslation } from 'react-i18next';

const ONE_HOUR = 3_600_000;

type TRelativeTimeProps = {
  date: Date | string;
  interval?: number;
  children: (relativeTime: string) => ReactNode;
};

// the apps' style: today and yesterday by name, anything older as a short date, all with the time
const getFormattedTime = (
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
const getUpdateInterval = (date: Date): number | null => {
  if (isToday(date) || isYesterday(date)) {
    return ONE_HOUR;
  }

  return null;
};

const RelativeTime = memo(
  ({
    date,
    interval, // optional override
    children
  }: TRelativeTimeProps) => {
    const dateLocale = useDateLocale();
    const { t } = useTranslation('common');
    const parsedDate = useMemo(
      () => (typeof date === 'string' ? new Date(date) : date),
      [date]
    );

    const [, setCounter] = useState(0);

    useEffect(() => {
      const updateInterval = interval ?? getUpdateInterval(parsedDate);

      // if no update interval is needed, don't set up a timer
      if (updateInterval === null) {
        return;
      }

      const timer = setInterval(() => {
        // force re-render to update the relative time display
        setCounter((prev) => prev + 1);
      }, updateInterval);

      return () => clearInterval(timer);
    }, [interval, parsedDate]);

    return children(getFormattedTime(parsedDate, dateLocale, t));
  }
);

export { RelativeTime };
