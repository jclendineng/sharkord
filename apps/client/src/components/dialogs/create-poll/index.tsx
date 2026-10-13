import { Emoji } from '@/components/emoji';
import { EmojiPicker } from '@/components/emoji-picker';
import type { TEmojiItem } from '@/components/tiptap-input/helpers';
import { getTRPCClient } from '@/lib/trpc';
import {
  getTrpcError,
  POLL_ANSWER_MAX_LENGTH,
  POLL_DEFAULT_DURATION_HOURS,
  POLL_DURATIONS_HOURS,
  POLL_MAX_ANSWERS,
  POLL_QUESTION_MAX_LENGTH
} from '@sharkord/shared';
import {
  AutoFocus,
  Button,
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  Group,
  IconButton,
  Input,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  Switch
} from '@sharkord/ui';
import { Plus, Smile, Trash2 } from 'lucide-react';
import { memo, useCallback, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';
import type { TDialogBaseProps } from '../types';

type TDraftAnswer = {
  key: number;
  text: string;
  emoji?: string;
};

type TAnswerRowProps = {
  answer: TDraftAnswer;
  canRemove: boolean;
  onChange: (key: number, change: Partial<TDraftAnswer>) => void;
  onRemove: (key: number) => void;
};

const AnswerRow = memo(
  ({ answer, canRemove, onChange, onRemove }: TAnswerRowProps) => {
    const { t } = useTranslation('dialogs');

    // only built in emoji, a custom one would need its file to render in the poll
    const onEmojiSelect = useCallback(
      (emoji: TEmojiItem) => {
        if (emoji.emoji) {
          onChange(answer.key, { emoji: emoji.shortcodes[0] });
        }
      },
      [answer.key, onChange]
    );

    const onTextChange = useCallback(
      (event: React.ChangeEvent<HTMLInputElement>) =>
        onChange(answer.key, { text: event.target.value }),
      [answer.key, onChange]
    );

    const onRemoveClick = useCallback(
      () => onRemove(answer.key),
      [answer.key, onRemove]
    );

    return (
      <div className="flex items-center gap-2">
        <EmojiPicker onEmojiSelect={onEmojiSelect}>
          <Button size="icon" variant="ghost" type="button">
            {answer.emoji ? (
              <Emoji emoji={answer.emoji} file={null} />
            ) : (
              <Smile className="h-4 w-4" />
            )}
          </Button>
        </EmojiPicker>
        <Input
          value={answer.text}
          onChange={onTextChange}
          maxLength={POLL_ANSWER_MAX_LENGTH}
          placeholder={t('pollAnswerPlaceholder')}
        />
        <IconButton
          icon={Trash2}
          variant="ghost"
          title={t('pollRemoveAnswer')}
          onClick={onRemoveClick}
          disabled={!canRemove}
        />
      </div>
    );
  }
);

type TCreatePollDialogProps = TDialogBaseProps & {
  channelId: number;
};

const CreatePollDialog = memo(
  ({ isOpen, close, channelId }: TCreatePollDialogProps) => {
    const { t } = useTranslation('dialogs');
    const [question, setQuestion] = useState('');
    const [answers, setAnswers] = useState<TDraftAnswer[]>([
      { key: 0, text: '' },
      { key: 1, text: '' }
    ]);
    const [nextKey, setNextKey] = useState(2);
    const [durationHours, setDurationHours] = useState(
      String(POLL_DEFAULT_DURATION_HOURS)
    );
    const [allowMultiple, setAllowMultiple] = useState(false);
    const [loading, setLoading] = useState(false);

    const filledAnswers = useMemo(
      () => answers.filter((answer) => answer.text.trim().length > 0),
      [answers]
    );

    const canPost =
      question.trim().length > 0 && filledAnswers.length > 0 && !loading;

    const onQuestionChange = useCallback(
      (event: React.ChangeEvent<HTMLInputElement>) =>
        setQuestion(event.target.value),
      []
    );

    const onAnswerChange = useCallback(
      (key: number, change: Partial<TDraftAnswer>) =>
        setAnswers((current) =>
          current.map((answer) =>
            answer.key === key ? { ...answer, ...change } : answer
          )
        ),
      []
    );

    const onAnswerRemove = useCallback(
      (key: number) =>
        setAnswers((current) => current.filter((answer) => answer.key !== key)),
      []
    );

    const onAddAnswer = useCallback(() => {
      setAnswers((current) => [...current, { key: nextKey, text: '' }]);
      setNextKey((key) => key + 1);
    }, [nextKey]);

    const onSubmit = useCallback(async () => {
      setLoading(true);

      try {
        const trpc = getTRPCClient();

        await trpc.polls.create.mutate({
          channelId,
          question: question.trim(),
          answers: filledAnswers.map(({ text, emoji }) => ({
            text: text.trim(),
            emoji
          })),
          durationHours: Number(durationHours),
          allowMultiple
        });

        close();
      } catch (error) {
        toast.error(getTrpcError(error, t('pollCreateFailed')));
      } finally {
        setLoading(false);
      }
    }, [
      channelId,
      question,
      filledAnswers,
      durationHours,
      allowMultiple,
      close,
      t
    ]);

    return (
      <Dialog open={isOpen}>
        <DialogContent onInteractOutside={close} close={close}>
          <DialogHeader>
            <DialogTitle>{t('createPollTitle')}</DialogTitle>
          </DialogHeader>

          <Group label={t('pollQuestionLabel')}>
            <AutoFocus>
              <Input
                value={question}
                onChange={onQuestionChange}
                maxLength={POLL_QUESTION_MAX_LENGTH}
                placeholder={t('pollQuestionPlaceholder')}
              />
            </AutoFocus>
          </Group>

          <Group label={t('pollAnswersLabel')}>
            <div className="flex flex-col gap-2">
              {answers.map((answer) => (
                <AnswerRow
                  key={answer.key}
                  answer={answer}
                  canRemove={answers.length > 1}
                  onChange={onAnswerChange}
                  onRemove={onAnswerRemove}
                />
              ))}
              {answers.length < POLL_MAX_ANSWERS && (
                <Button
                  variant="ghost"
                  className="self-start"
                  onClick={onAddAnswer}
                >
                  <Plus className="h-4 w-4" />
                  {t('pollAddAnswer')}
                </Button>
              )}
            </div>
          </Group>

          <Group label={t('pollDurationLabel')}>
            <Select value={durationHours} onValueChange={setDurationHours}>
              <SelectTrigger className="w-[200px]">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {POLL_DURATIONS_HOURS.map((hours) => (
                  <SelectItem key={hours} value={String(hours)}>
                    {t(`pollDuration${hours}`)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Group>

          <Group label={t('pollAllowMultipleLabel')}>
            <Switch
              checked={allowMultiple}
              onCheckedChange={setAllowMultiple}
            />
          </Group>

          <DialogFooter className="gap-2">
            <Button variant="ghost" onClick={close}>
              {t('cancel')}
            </Button>
            <Button onClick={onSubmit} disabled={!canPost}>
              {t('pollPostBtn')}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    );
  }
);

export { CreatePollDialog };
