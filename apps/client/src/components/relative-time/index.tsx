import { useDateLocale } from '@/hooks/use-date-locale';
import { memo, useEffect, useMemo, useState, type ReactNode } from 'react';
import { useTranslation } from 'react-i18next';
import { getFormattedTime, getUpdateInterval } from './helpers';

type TRelativeTimeProps = {
  date: Date | string;
  interval?: number;
  children: (relativeTime: string) => ReactNode;
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
