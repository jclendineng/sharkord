import {
  ChannelPermission,
  Permission,
  POLL_ANSWER_MAX_LENGTH,
  POLL_DURATIONS_HOURS,
  POLL_MAX_ANSWERS,
  POLL_MIN_ANSWERS,
  POLL_QUESTION_MAX_LENGTH,
  REACTION_EMOJI_MAX_LENGTH
} from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { publishMessage } from '../../db/publishers';
import { assertDmChannel } from '../../db/queries/dms';
import { messages, pollAnswers, polls } from '../../db/schema';
import { eventBus } from '../../plugins/event-bus';
import { enqueuePushNotification } from '../../queues/push-notifications';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const HOUR_MS = 60 * 60 * 1000;

// a poll is a message of its own with no text, and like a message it can't be edited after
const createPollRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.sendAndEditMessage.maxRequests,
  windowMs: config.rateLimiters.sendAndEditMessage.windowMs,
  logLabel: 'createPoll'
})
  .input(
    z.object({
      channelId: z.number(),
      question: z.string().trim().min(1).max(POLL_QUESTION_MAX_LENGTH),
      answers: z
        .array(
          z.object({
            text: z.string().trim().min(1).max(POLL_ANSWER_MAX_LENGTH),
            emoji: z.string().min(1).max(REACTION_EMOJI_MAX_LENGTH).optional()
          })
        )
        .min(POLL_MIN_ANSWERS)
        .max(POLL_MAX_ANSWERS),
      durationHours: z
        .number()
        .refine(
          (hours) => POLL_DURATIONS_HOURS.some((value) => value === hours),
          {
            message: 'That poll length is not available.'
          }
        ),
      allowMultiple: z.boolean()
    })
  )
  .mutation(async ({ input, ctx }) => {
    await Promise.all([
      ctx.needsPermission(Permission.SEND_MESSAGES),
      ctx.needsChannelPermission(
        input.channelId,
        ChannelPermission.SEND_MESSAGES
      )
    ]);

    await assertDmChannel(input.channelId, ctx.userId);

    const texts = input.answers.map(({ text }) => text.toLowerCase());

    invariant(new Set(texts).size === texts.length, {
      code: 'BAD_REQUEST',
      message: 'Each answer has to be different.'
    });

    const now = Date.now();

    const message = db.transaction((tx) => {
      const createdMessage = tx
        .insert(messages)
        .values({
          channelId: input.channelId,
          userId: ctx.userId,
          content: '',
          editable: false,
          createdAt: now
        })
        .returning()
        .get();

      tx.insert(polls)
        .values({
          messageId: createdMessage.id,
          question: input.question,
          allowMultiple: input.allowMultiple,
          expiresAt: now + input.durationHours * HOUR_MS,
          createdAt: now
        })
        .run();

      tx.insert(pollAnswers)
        .values(
          input.answers.map((answer, position) => ({
            messageId: createdMessage.id,
            position,
            text: answer.text,
            emoji: answer.emoji ?? null
          }))
        )
        .run();

      return createdMessage;
    });

    publishMessage(message.id, input.channelId, 'create');
    enqueuePushNotification(message.id);

    eventBus.emit('message:created', {
      messageId: message.id,
      channelId: input.channelId,
      userId: ctx.userId,
      pluginId: null,
      content: '',
      textContent: input.question
    });

    return message.id;
  });

export { createPollRoute };
