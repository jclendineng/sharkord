import { getTRPCClient } from '@/lib/trpc';
import { getTrpcError, USER_NOTE_MAX_LENGTH } from '@sharkord/shared';
import { Textarea } from '@sharkord/ui';
import { memo, useCallback, useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';

type TUserNoteProps = {
  userId: number;
};

// discord's note on a profile, only ever seen by whoever wrote it, saved when the field is left.
// a server from before notes has none, and the field stays away
const UserNote = memo(({ userId }: TUserNoteProps) => {
  const { t } = useTranslation();
  const [note, setNote] = useState('');
  const [saved, setSaved] = useState<string>();

  useEffect(() => {
    let cancelled = false;

    const load = async () => {
      try {
        const trpc = getTRPCClient();
        const loaded = await trpc.users.getNote.query({ userId });

        if (!cancelled) {
          setNote(loaded);
          setSaved(loaded);
        }
      } catch {
        // no notes on this server
      }
    };

    load();

    return () => {
      cancelled = true;
    };
  }, [userId]);

  const onChange = useCallback(
    (event: React.ChangeEvent<HTMLTextAreaElement>) => {
      setNote(event.target.value);
    },
    []
  );

  const onBlur = useCallback(async () => {
    const text = note.trim();

    if (text === saved) {
      return;
    }

    setSaved(text);

    try {
      const trpc = getTRPCClient();

      await trpc.users.setNote.mutate({ userId, note: text });
    } catch (error) {
      toast.error(getTrpcError(error, t('failedSaveNote')));
    }
  }, [note, saved, t, userId]);

  if (saved === undefined) {
    return null;
  }

  return (
    <div className="mt-3">
      <p className="mb-1 text-xs font-semibold text-muted-foreground">
        {t('noteLabel')}
      </p>
      <Textarea
        value={note}
        onChange={onChange}
        onBlur={onBlur}
        maxLength={USER_NOTE_MAX_LENGTH}
        placeholder={t('notePlaceholder')}
        className="min-h-9 resize-none text-sm"
        rows={1}
      />
    </div>
  );
});

export { UserNote };
