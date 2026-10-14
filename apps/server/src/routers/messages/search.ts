import { getPlainTextFromHtml, hasMention, type TFile } from '@sharkord/shared';
import {
  and,
  desc,
  eq,
  exists,
  gt,
  gte,
  inArray,
  isNotNull,
  lt,
  or,
  sql
} from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { getChannelsForUser } from '../../db/queries/channels';
import { getSettings } from '../../db/queries/server';
import {
  channels,
  files,
  messageFiles,
  messages,
  polls
} from '../../db/schema';
import { attachFileToken } from '../../helpers/files-crypto';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// this search is pretty basic and it CAN be optimized, however it might not be worth it
// some things things we can do:
// check https://sqlite.org/fts5.html for full text search capabilities, but it might be an overkill and add complexity to the codebase
// save an already pre-processed plain text version of the message content in the database to avoid having to do it in JS and speed up the search (this would require updating the existing messages and keeping it in sync for new messages, but it would make the search much faster and more accurate)
// for files the same applies, we could save a pre-processed version of the original name in lowercase to speed up the search and make it more accurate
// however, the quick test I did with close to 10k messages the request was taking around 4-8 ms, which is more than good enough

const SEARCH_QUERY_MIN_LENGTH = 2; // minimum length for search query to prevent too broad searches
const SEARCH_QUERY_MAX_LENGTH = 24; // maximum length for search query to prevent performance issues and potential abuse
const MESSAGE_FETCH_MULTIPLIER = 4; // multiplier to fetch more messages than requested to account for filtering after fetching from the database
const MAX_MESSAGE_FETCH_LIMIT = 100; // absolute maximum number of messages to fetch from the database before filtering, to prevent performance issues

const MESSAGES_LIMIT = 25;
const DAY_MS = 24 * 60 * 60 * 1000;
const FILES_LIMIT = 25;

const GLOB_SPECIAL_CHARS = new Set(['*', '?', '[']);

const buildCaseInsensitiveGlob = (value: string) => {
  let pattern = '';

  for (const char of value) {
    const upper = char.toUpperCase();

    if (upper !== char && [...upper].length === 1) {
      pattern += `[${char}${upper}]`;
    } else if (GLOB_SPECIAL_CHARS.has(char)) {
      pattern += `[${char}]`;
    } else {
      pattern += char;
    }
  }

  return `*${pattern}*`;
};

const searchMessagesRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.search.maxRequests,
  windowMs: config.rateLimiters.search.windowMs,
  logLabel: 'search'
})
  .input(
    z
      .object({
        query: z
          .string()
          .trim()
          .toLowerCase()
          .min(SEARCH_QUERY_MIN_LENGTH)
          .max(SEARCH_QUERY_MAX_LENGTH)
          .optional(),
        // discord's filters: from:, in:, mentions:, has:, before:, after: and during:
        fromUserId: z.number().int().positive().optional(),
        channelId: z.number().int().positive().optional(),
        mentionsUserId: z.number().int().positive().optional(),
        has: z
          .enum(['file', 'image', 'video', 'link', 'poll', 'sticker'])
          .optional(),
        before: z.number().int().nonnegative().optional(),
        after: z.number().int().nonnegative().optional(),
        // the start of a day, the whole day from there is searched
        on: z.number().int().nonnegative().optional()
      })
      .refine(
        ({ query, ...filters }) =>
          query !== undefined ||
          Object.values(filters).some((value) => value !== undefined),
        { message: 'Enter something to search for or pick a filter.' }
      )
  )
  .query(async ({ ctx, input }) => {
    const settings = await getSettings();

    invariant(settings.enableSearch, {
      code: 'FORBIDDEN',
      message: 'Search is disabled on this server'
    });

    const accessibleChannels = await getChannelsForUser(ctx.userId);

    // getChannelsForUser only returns the direct messages the caller takes part in, the
    // owner included, so their conversations are searched along with the channels
    const accessibleChannelIds = accessibleChannels
      .map((channel) => channel.id)
      .filter((id) => input.channelId === undefined || id === input.channelId);

    if (accessibleChannelIds.length === 0) {
      return {
        messages: [],
        files: [],
        truncated: false
      };
    }

    const globPattern = input.query
      ? buildCaseInsensitiveGlob(input.query)
      : undefined;

    // the filters that narrow messages and files alike
    const shared = [
      inArray(messages.channelId, accessibleChannelIds),
      input.fromUserId ? eq(messages.userId, input.fromUserId) : undefined,
      input.before ? lt(messages.createdAt, input.before) : undefined,
      input.after ? gt(messages.createdAt, input.after) : undefined,
      input.on !== undefined ? gte(messages.createdAt, input.on) : undefined,
      input.on !== undefined
        ? lt(messages.createdAt, input.on + DAY_MS)
        : undefined
    ];

    const hasFilter = {
      file: exists(
        db
          .select({ id: messageFiles.messageId })
          .from(messageFiles)
          .where(eq(messageFiles.messageId, messages.id))
      ),
      // an uploaded picture, or a gif or picture shown from a link, like one from the picker
      image: or(
        exists(
          db
            .select({ id: messageFiles.messageId })
            .from(messageFiles)
            .innerJoin(files, eq(files.id, messageFiles.fileId))
            .where(
              and(
                eq(messageFiles.messageId, messages.id),
                sql`${files.mimeType} GLOB 'image/*'`
              )
            )
        ),
        sql`EXISTS (SELECT 1 FROM json_each(${messages.metadata}) WHERE json_extract(value, '$.kind') = 'media' AND json_extract(value, '$.mediaType') = 'image')`
      ),
      video: exists(
        db
          .select({ id: messageFiles.messageId })
          .from(messageFiles)
          .innerJoin(files, eq(files.id, messageFiles.fileId))
          .where(
            and(
              eq(messageFiles.messageId, messages.id),
              sql`${files.mimeType} GLOB 'video/*'`
            )
          )
      ),
      // a link in the html, or a bare domain the server found and fetched a preview for
      link: or(
        sql`${messages.content} GLOB '*href="http*'`,
        sql`EXISTS (SELECT 1 FROM json_each(${messages.metadata}) WHERE json_extract(value, '$.kind') = 'open_graph')`
      ),
      poll: exists(
        db
          .select({ id: polls.messageId })
          .from(polls)
          .where(eq(polls.messageId, messages.id))
      ),
      sticker: isNotNull(messages.stickerId)
    };

    // the kinds a file can be, the rest live in the message and leave no file results
    const fileKinds: (string | undefined)[] = [
      undefined,
      'file',
      'image',
      'video'
    ];

    // a mention, a link, a poll or a sticker lives in a message, not in a file
    const searchesFiles =
      input.mentionsUserId === undefined &&
      fileKinds.includes(input.has) &&
      (globPattern !== undefined || input.has !== undefined);

    const messageFetchLimit = Math.min(
      MESSAGES_LIMIT * MESSAGE_FETCH_MULTIPLIER,
      MAX_MESSAGE_FETCH_LIMIT
    );

    const [messageRows, fileRows] = await Promise.all([
      db
        .select({
          message: messages,
          channelName: channels.name,
          channelIsDm: channels.isDm
        })
        .from(messages)
        .innerJoin(channels, eq(channels.id, messages.channelId))
        .where(
          and(
            ...shared,
            globPattern
              ? sql`${messages.content} GLOB ${globPattern}`
              : undefined,
            input.mentionsUserId
              ? sql`${messages.content} GLOB ${`*data-user-id="${input.mentionsUserId}"*`}`
              : undefined,
            input.has ? hasFilter[input.has] : undefined
          )
        )
        .orderBy(desc(messages.createdAt))
        .limit(messageFetchLimit),
      searchesFiles
        ? db
            .select({
              file: files,
              messageId: messages.id,
              channelId: messages.channelId,
              messageContent: messages.content,
              messageCreatedAt: messages.createdAt,
              channelName: channels.name,
              channelIsDm: channels.isDm
            })
            .from(messageFiles)
            .innerJoin(files, eq(files.id, messageFiles.fileId))
            .innerJoin(messages, eq(messages.id, messageFiles.messageId))
            .innerJoin(channels, eq(channels.id, messages.channelId))
            .where(
              and(
                ...shared,
                globPattern
                  ? sql`${files.originalName} GLOB ${globPattern}`
                  : undefined,
                input.has === 'image'
                  ? sql`${files.mimeType} GLOB 'image/*'`
                  : undefined,
                input.has === 'video'
                  ? sql`${files.mimeType} GLOB 'video/*'`
                  : undefined
              )
            )
            .orderBy(desc(messages.createdAt))
            .limit(FILES_LIMIT)
        : []
    ]);

    const matchedMessages = messageRows
      .map((row) => {
        const plainContent = getPlainTextFromHtml(
          row.message.content ?? ''
        ).trim();

        return {
          ...row,
          plainContent
        };
      })
      .filter((row) => {
        if (
          input.mentionsUserId &&
          !hasMention(row.message.content, input.mentionsUserId)
        ) {
          return false;
        }

        // without words to look for, the filters alone decide
        if (!input.query) {
          return true;
        }

        return row.plainContent.toLowerCase().includes(input.query);
      })
      .slice(0, MESSAGES_LIMIT);

    const matchedMessageIds = matchedMessages.map((row) => row.message.id);

    const attachedFileRows =
      matchedMessageIds.length > 0
        ? await db
            .select({
              messageId: messageFiles.messageId,
              file: files
            })
            .from(messageFiles)
            .innerJoin(files, eq(files.id, messageFiles.fileId))
            .where(inArray(messageFiles.messageId, matchedMessageIds))
        : [];

    const filesByMessageId = new Map<number, TFile[]>();

    for (const row of attachedFileRows) {
      const list = filesByMessageId.get(row.messageId) ?? [];

      list.push({ ...row.file });
      filesByMessageId.set(row.messageId, list);
    }

    const matchedMessagesWithFiles = matchedMessages.map((row) => {
      const attachedFiles = filesByMessageId.get(row.message.id) ?? [];

      const preparedFiles = attachedFiles.map((file) =>
        attachFileToken(
          file,
          settings.storageSignedUrlsEnabled,
          settings.storageSignedUrlsTtlSeconds
        )
      );

      return {
        ...row.message,
        channelName: row.channelName,
        channelIsDm: row.channelIsDm,
        plainContent: row.plainContent,
        files: preparedFiles,
        reactions: [],
        poll: null,
        sticker: null
      };
    });

    const matchedFiles = fileRows.map((row) => {
      const file = attachFileToken(
        row.file,
        settings.storageSignedUrlsEnabled,
        settings.storageSignedUrlsTtlSeconds
      );

      return {
        file,
        messageId: row.messageId,
        channelId: row.channelId,
        messageContent: row.messageContent,
        messageCreatedAt: row.messageCreatedAt,
        channelName: row.channelName,
        channelIsDm: row.channelIsDm
      };
    });

    const truncated =
      messageRows.length >= messageFetchLimit ||
      fileRows.length >= FILES_LIMIT ||
      matchedMessages.length >= MESSAGES_LIMIT;

    return {
      messages: matchedMessagesWithFiles,
      files: matchedFiles,
      truncated
    };
  });

export { searchMessagesRoute };
