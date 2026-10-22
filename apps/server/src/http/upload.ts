import { getErrorMessage, UploadHeaders } from '@sharkord/shared';
import fs from 'fs';
import http from 'http';
import z from 'zod';
import { config } from '../config';
import { getSettings } from '../db/queries/server';
import { getUserByToken } from '../db/queries/users';
import { fileManager } from '../helpers/file-manager';
import { getWsInfo } from '../helpers/get-ws-info';
import { logger } from '../logger';
import { createRateLimiter } from '../utils/rate-limiters/rate-limiter';
import {
  enforceHttpRateLimit,
  sanitizeFileName,
  sendJsonError
} from './helpers';

const zHeaders = z.object({
  [UploadHeaders.TOKEN]: z.string(),
  [UploadHeaders.ORIGINAL_NAME]: z.string(),
  [UploadHeaders.CONTENT_LENGTH]: z.coerce.number().int().nonnegative()
});

const uploadRateLimiter = createRateLimiter({
  maxRequests: config.rateLimiters.upload.maxRequests,
  windowMs: config.rateLimiters.upload.windowMs
});

const uploadFileRouteHandler = async (
  req: http.IncomingMessage,
  res: http.ServerResponse
) => {
  const allowed = enforceHttpRateLimit(
    res,
    uploadRateLimiter,
    getWsInfo(undefined, req)?.ip,
    {
      route: '/upload',
      message: 'Too many uploads. Please try again shortly.'
    }
  );

  if (!allowed) {
    req.resume();

    return;
  }

  const parsedHeaders = zHeaders.parse(req.headers);

  const [token, rawOriginalName, contentLength] = [
    parsedHeaders[UploadHeaders.TOKEN],
    parsedHeaders[UploadHeaders.ORIGINAL_NAME],
    parsedHeaders[UploadHeaders.CONTENT_LENGTH]
  ];

  const originalName = sanitizeFileName(rawOriginalName);

  if (!originalName) {
    req.resume();
    sendJsonError(res, 400, 'Invalid file name');
    return;
  }

  const user = await getUserByToken(token);

  if (!user) {
    req.resume();
    sendJsonError(res, 401, 'Unauthorized');
    return;
  }

  // no UPLOAD_FILES check here: an upload is only a temporary file, and each route that keeps
  // one checks its own permission. attaching to a message needs UPLOAD_FILES, while an avatar
  // or banner needs nothing, so turning off file sharing still lets people set a picture
  const settings = await getSettings();

  if (contentLength > settings.storageUploadMaxFileSize) {
    req.resume();
    req.on('end', () => {
      sendJsonError(
        res,
        413,
        `File ${originalName} exceeds the maximum allowed size`
      );
    });

    return;
  }

  if (!settings.storageUploadEnabled) {
    req.resume();
    req.on('end', () => {
      sendJsonError(res, 403, 'File uploads are disabled on this server');
    });

    return;
  }

  const safePath = await fileManager.getSafeUploadPath(originalName);
  const fileStream = fs.createWriteStream(safePath);

  let failed = false;

  // a client that disconnects mid body leaves a partial file and an open descriptor behind
  // unless the write is torn down here. a body longer than content-length cannot arrive: the
  // parser frames it by that header and refuses one that also says chunked
  const abortUpload = async (status?: number, message?: string) => {
    if (failed) return;

    failed = true;

    req.unpipe(fileStream);
    fileStream.destroy();

    if (status && message && !res.headersSent) {
      sendJsonError(res, status, message);
    }

    await fs.promises.rm(safePath, { force: true });
  };

  req.on('close', () => {
    if (req.complete) return;

    abortUpload().catch((error) => {
      logger.error(
        'Error cleaning up aborted upload: %s',
        getErrorMessage(error)
      );
    });
  });

  req.pipe(fileStream);

  fileStream.on('finish', async () => {
    if (failed) return;

    try {
      const { size } = await fs.promises.stat(safePath);

      if (size !== contentLength) {
        await fs.promises.rm(safePath, { force: true });
        sendJsonError(res, 400, 'Upload did not match the declared size');

        return;
      }

      const tempFile = await fileManager.addTemporaryFile({
        originalName,
        filePath: safePath,
        size,
        userId: user.id
      });

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(tempFile));
    } catch (error) {
      logger.error(
        'Error processing uploaded file: %s',
        getErrorMessage(error)
      );
      sendJsonError(res, 500, 'File processing failed');
    }
  });

  fileStream.on('error', (err) => {
    logger.error('Error uploading file: %s', getErrorMessage(err));

    abortUpload(500, 'File upload failed').catch((error) => {
      logger.error(
        'Error cleaning up failed upload: %s',
        getErrorMessage(error)
      );
    });
  });
};

export { uploadFileRouteHandler };
