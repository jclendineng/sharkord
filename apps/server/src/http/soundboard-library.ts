import { SOUNDBOARD_LIBRARY } from '@sharkord/shared';
import http from 'http';
import path from 'path';
import { getSoundboardLibraryFile } from '../helpers/soundboard-library';
import { sendJsonError } from './helpers';

// the library's sounds to preview before one is added. open without signing in, since they
// are the same cc0 clips on every server and say nothing about this one
const soundboardLibraryRouteHandler = async (
  _req: http.IncomingMessage,
  res: http.ServerResponse,
  { url }: { url: URL }
) => {
  const key = path.basename(url.pathname, '.m4a');
  const entry = SOUNDBOARD_LIBRARY.find((sound) => sound.key === key);

  if (!entry) {
    sendJsonError(res, 404, 'Sound not found');

    return;
  }

  // read whole rather than streamed: they are a few kilobytes each, and an embedded file in
  // the compiled server can only be read through Bun.file
  const bytes = await Bun.file(getSoundboardLibraryFile(entry.key)).bytes();

  res.writeHead(200, {
    'Content-Type': 'audio/mp4',
    'Content-Length': bytes.byteLength,
    'Cache-Control': 'public, max-age=86400'
  });
  res.end(bytes);
};

export { soundboardLibraryRouteHandler };
