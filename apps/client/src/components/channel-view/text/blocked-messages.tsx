import { memo, useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';

type TBlockedMessagesProps = {
  count: number;
  children: React.ReactNode;
};

// a blocked person's stretch of messages folds into one row, opened on asking, as discord does
const BlockedMessages = memo(({ count, children }: TBlockedMessagesProps) => {
  const { t } = useTranslation();
  const [isShown, setIsShown] = useState(false);

  const onToggle = useCallback(() => {
    setIsShown((shown) => !shown);
  }, []);

  return (
    <div>
      <div className="flex items-center gap-2 px-4 pt-2 text-sm text-muted-foreground">
        <span>{t('blockedMessages', { count })}</span>
        <span aria-hidden>·</span>
        <button
          type="button"
          className="hover:underline focus-visible:underline"
          onClick={onToggle}
        >
          {isShown ? t('hideBlockedMessages') : t('showBlockedMessages')}
        </button>
      </div>
      {isShown && children}
    </div>
  );
});

export { BlockedMessages };
