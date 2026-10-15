import { usePublicServerSettings } from '@/features/server/hooks';
import { BadgeCheck } from 'lucide-react';
import { memo } from 'react';
import { useTranslation } from 'react-i18next';

type TRulesNoteProps = {
  messageId: number;
};

// under the server's rules message, saying what reacting to it does
const RulesNote = memo(({ messageId }: TRulesNoteProps) => {
  const { t } = useTranslation();
  const settings = usePublicServerSettings();

  if (settings?.onboardingMessageId !== messageId) {
    return null;
  }

  return (
    <div className="mt-1 flex items-center gap-1.5 text-xs text-muted-foreground">
      <BadgeCheck className="h-3.5 w-3.5 shrink-0" />
      <span>{t('rulesNote')}</span>
    </div>
  );
});

export { RulesNote };
