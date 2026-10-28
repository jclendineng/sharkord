import { Emoji } from '@/components/emoji';
import { useCan } from '@/features/server/hooks';
import { useOwnUserId } from '@/features/server/users/hooks';
import { getTRPCClient } from '@/lib/trpc';
import { cn } from '@/lib/utils';
import {
  getTrpcError,
  Permission,
  type TJoinedPoll,
  type TJoinedPollAnswer
} from '@sharkord/shared';
import { Button } from '@sharkord/ui';
import { Check, Crown } from 'lucide-react';
import { memo, useCallback, useEffect, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';

const MINUTE_MS = 60 * 1000;

// re-renders once a minute so the time left and the closing of the poll follow the clock
const useNow = () => {
  const [now, setNow] = useState(Date.now);

  useEffect(() => {
    const interval = setInterval(() => setNow(Date.now()), MINUTE_MS);

    return () => clearInterval(interval);
  }, []);

  return now;
};

type TPollAnswerRowProps = {
  answer: TJoinedPollAnswer;
  total: number;
  showsResults: boolean;
  isPicked: boolean;
  isWinner: boolean;
  onPick: (answerId: number) => void;
};

const PollAnswerRow = memo(
  ({
    answer,
    total,
    showsResults,
    isPicked,
    isWinner,
    onPick
  }: TPollAnswerRowProps) => {
    const share = total === 0 ? 0 : answer.userIds.length / total;
    const percent = Math.round(share * 100);

    const onClick = useCallback(() => onPick(answer.id), [answer.id, onPick]);

    return (
      <button
        type="button"
        onClick={onClick}
        disabled={showsResults}
        className={cn(
          'relative flex w-full items-center gap-2 overflow-hidden rounded-md border bg-muted/40 px-3 py-2 text-left text-sm',
          isPicked ? 'border-primary' : 'border-transparent',
          !showsResults && 'hover:bg-muted'
        )}
      >
        {showsResults && (
          <span
            className={cn(
              'absolute inset-y-0 left-0',
              isPicked ? 'bg-primary/30' : 'bg-muted-foreground/20'
            )}
            style={{ width: `${percent}%` }}
          />
        )}
        <span className="relative flex flex-1 items-center gap-2">
          {answer.emoji && <Emoji emoji={answer.emoji} file={null} />}
          <span className="font-medium">{answer.text}</span>
        </span>
        {showsResults && (
          <span className="relative flex items-center gap-1 text-xs font-semibold tabular-nums">
            {isWinner && <Crown className="h-3 w-3 text-yellow-500" />}
            {answer.userIds.length} · {percent}%
          </span>
        )}
        {isPicked && <Check className="relative h-4 w-4 text-primary" />}
      </button>
    );
  }
);

type TPollProps = {
  messageId: number;
  authorId: number | null;
  poll: TJoinedPoll;
};

const Poll = memo(({ messageId, authorId, poll }: TPollProps) => {
  const { t } = useTranslation('common');
  const ownUserId = useOwnUserId();
  const can = useCan();
  const now = useNow();
  const [picked, setPicked] = useState<number[]>([]);
  const [working, setWorking] = useState(false);

  const ownVotes = useMemo(
    () =>
      poll.answers
        .filter((answer) => ownUserId && answer.userIds.includes(ownUserId))
        .map((answer) => answer.id),
    [poll.answers, ownUserId]
  );

  const voterCount = useMemo(
    () => new Set(poll.answers.flatMap((answer) => answer.userIds)).size,
    [poll.answers]
  );

  const mostVotes = useMemo(
    () => Math.max(0, ...poll.answers.map((answer) => answer.userIds.length)),
    [poll.answers]
  );

  const isClosed = poll.endedAt !== null || poll.expiresAt <= now;
  const showsResults = isClosed || ownVotes.length > 0;
  const canEnd =
    !isClosed && (authorId === ownUserId || can(Permission.MANAGE_MESSAGES));

  const status = useMemo(() => {
    const votes = t('pollVotes', { count: voterCount });

    if (isClosed) {
      return `${votes} · ${t('pollClosed')}`;
    }

    const hours = Math.floor((poll.expiresAt - now) / (60 * MINUTE_MS));

    if (hours >= 24) {
      return `${votes} · ${t('pollDaysLeft', { count: Math.floor(hours / 24) })}`;
    }

    if (hours >= 1) {
      return `${votes} · ${t('pollHoursLeft', { count: hours })}`;
    }

    const minutes = Math.max(1, Math.floor((poll.expiresAt - now) / MINUTE_MS));

    return `${votes} · ${t('pollMinutesLeft', { count: minutes })}`;
  }, [t, voterCount, isClosed, poll.expiresAt, now]);

  const onPick = useCallback(
    (answerId: number) =>
      setPicked((current) => {
        if (!poll.allowMultiple) {
          return [answerId];
        }

        return current.includes(answerId)
          ? current.filter((id) => id !== answerId)
          : [...current, answerId];
      }),
    [poll.allowMultiple]
  );

  const submit = useCallback(
    async (answerIds: number[]) => {
      setWorking(true);

      try {
        const trpc = getTRPCClient();

        await trpc.polls.vote.mutate({ messageId, answerIds });

        setPicked([]);
      } catch (error) {
        toast.error(getTrpcError(error, t('pollVoteFailed')));
      } finally {
        setWorking(false);
      }
    },
    [messageId, t]
  );

  const onVote = useCallback(() => submit(picked), [submit, picked]);
  const onRemoveVote = useCallback(() => submit([]), [submit]);

  const onEnd = useCallback(async () => {
    setWorking(true);

    try {
      const trpc = getTRPCClient();

      await trpc.polls.end.mutate({ messageId });
    } catch (error) {
      toast.error(getTrpcError(error, t('pollEndFailed')));
    } finally {
      setWorking(false);
    }
  }, [messageId, t]);

  return (
    <div className="flex max-w-md flex-col gap-3 rounded-lg border bg-card p-4">
      <div>
        <div className="font-semibold">{poll.question}</div>
        <div className="text-xs text-muted-foreground">
          {poll.allowMultiple ? t('pollSelectMany') : t('pollSelectOne')}
        </div>
      </div>

      <div className="flex flex-col gap-1.5">
        {poll.answers.map((answer) => (
          <PollAnswerRow
            key={answer.id}
            answer={answer}
            total={voterCount}
            showsResults={showsResults}
            isPicked={
              showsResults
                ? ownVotes.includes(answer.id)
                : picked.includes(answer.id)
            }
            isWinner={
              isClosed && mostVotes > 0 && answer.userIds.length === mostVotes
            }
            onPick={onPick}
          />
        ))}
      </div>

      <div className="flex items-center gap-2">
        <span className="flex-1 text-xs text-muted-foreground">{status}</span>
        {canEnd && (
          <Button size="sm" variant="ghost" onClick={onEnd} disabled={working}>
            {t('pollEnd')}
          </Button>
        )}
        {!isClosed && ownVotes.length > 0 && (
          <Button
            size="sm"
            variant="secondary"
            onClick={onRemoveVote}
            disabled={working}
          >
            {t('pollRemoveVote')}
          </Button>
        )}
        {!showsResults && (
          <Button
            size="sm"
            onClick={onVote}
            disabled={working || picked.length === 0}
          >
            {t('pollVote')}
          </Button>
        )}
      </div>
    </div>
  );
});

export { Poll };
