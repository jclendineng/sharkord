import { z } from 'zod';
import { config } from '../../config';
import { getFileReferences } from '../../db/queries/files';
import { getSettings } from '../../db/queries/server';
import { canAccessChannel } from '../../helpers/assert-channel-access';
import { generateFileToken } from '../../helpers/files-crypto';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// fresh signed links for files a client already shows, so a page left open past the link
// lifetime keeps working without loading everything again. a file the caller cannot see, or
// that does not exist, is left out rather than rejected, so the answer never tells them apart
const signFilesRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.getMessages.maxRequests,
  windowMs: config.rateLimiters.getMessages.windowMs,
  logLabel: 'signFiles'
})
  .input(
    z.object({
      fileIds: z.array(z.number().int().positive()).min(1).max(200)
    })
  )
  .query(async ({ ctx, input }) => {
    const { storageSignedUrlsEnabled, storageSignedUrlsTtlSeconds } =
      await getSettings();

    // unsigned links never expire, there is nothing to refresh
    if (!storageSignedUrlsEnabled) {
      return [];
    }

    const fileIds = [...new Set(input.fileIds)];
    const { everyoneFileIds, channelFiles } = await getFileReferences(fileIds);

    const channelIds = [
      ...new Set(channelFiles.map(({ channelId }) => channelId))
    ];
    const access = await Promise.all(
      channelIds.map((channelId) => canAccessChannel(ctx, channelId))
    );
    const visibleChannelIds = new Set(
      channelIds.filter((_, index) => access[index])
    );

    const visibleFileIds = new Set(everyoneFileIds);

    for (const { fileId, channelId } of channelFiles) {
      if (visibleChannelIds.has(channelId)) {
        visibleFileIds.add(fileId);
      }
    }

    const expiresAt = Date.now() + storageSignedUrlsTtlSeconds * 1000;

    return [...visibleFileIds].map((fileId) => ({
      fileId,
      accessToken: generateFileToken(fileId, expiresAt),
      expiresAt
    }));
  });

export { signFilesRoute };
