import { PLUGIN_SDK_VERSION } from '@sharkord/shared';
import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import fs from 'fs/promises';
import os from 'os';
import path from 'path';
import { assertNoLinks, downloadFile, downloadPlugin } from '../downloads';
import { PLUGINS_PATH } from '../paths';

const MAX_DOWNLOAD_BYTES = 20 * 1024 * 1024;

const CHUNK = new Uint8Array(1024 * 1024);

// pull driven rather than pushed up front, so a client that gives up early stops the body
// being produced at all and the cap is reached rather than buffered
const oversizedStream = () => {
  let sent = 0;

  return new ReadableStream({
    pull(controller) {
      if (sent > MAX_DOWNLOAD_BYTES) {
        controller.close();

        return;
      }

      sent += CHUNK.byteLength;
      controller.enqueue(CHUNK);
    }
  });
};

const manifest = (id: string, sdkVersion = PLUGIN_SDK_VERSION) =>
  JSON.stringify({
    id,
    name: id,
    author: 'test',
    description: 'test plugin',
    sdkVersion,
    version: '1.0.0'
  });

const pluginArchive = (
  id: string,
  extra: Record<string, string> = {},
  sdkVersion = PLUGIN_SDK_VERSION
) =>
  new Bun.Archive({
    [`${id}/manifest.json`]: manifest(id, sdkVersion),
    [`${id}/server/index.js`]: 'export const onLoad = () => {};',
    [`${id}/client/index.js`]: 'export const components = {};',
    ...extra
  });

const archives = new Map<string, { bytes: Uint8Array; checksum: string }>();

type TTarEntry =
  | { name: string; type: 'file'; content: string }
  | { name: string; type: 'symlink'; linkName: string };

// a minimal ustar writer, enough for the link entries Bun.Archive will not create
const buildTar = (entries: TTarEntry[]): Uint8Array => {
  const encoder = new TextEncoder();
  const blocks: Uint8Array[] = [];

  const writeField = (
    header: Uint8Array,
    offset: number,
    length: number,
    value: string
  ) => {
    header.set(encoder.encode(value).subarray(0, length), offset);
  };

  const octal = (value: number, length: number) =>
    `${value.toString(8).padStart(length - 1, '0')}\0`;

  for (const entry of entries) {
    const content =
      entry.type === 'file' ? encoder.encode(entry.content) : new Uint8Array();
    const header = new Uint8Array(512);

    writeField(header, 0, 100, entry.name);
    writeField(header, 100, 8, octal(entry.type === 'file' ? 0o644 : 0o777, 8));
    writeField(header, 108, 8, octal(0, 8));
    writeField(header, 116, 8, octal(0, 8));
    writeField(header, 124, 12, octal(content.length, 12));
    writeField(header, 136, 12, octal(0, 12));
    writeField(header, 148, 8, '        ');
    writeField(header, 156, 1, entry.type === 'file' ? '0' : '2');

    if (entry.type === 'symlink') {
      writeField(header, 157, 100, entry.linkName);
    }

    writeField(header, 257, 6, 'ustar\0');
    writeField(header, 263, 2, '00');

    const checksum = header.reduce((sum, byte) => sum + byte, 0);

    writeField(header, 148, 8, `${checksum.toString(8).padStart(6, '0')}\0 `);

    blocks.push(header);

    if (content.length > 0) {
      const padded = new Uint8Array(Math.ceil(content.length / 512) * 512);

      padded.set(content);
      blocks.push(padded);
    }
  }

  blocks.push(new Uint8Array(1024));

  const tar = new Uint8Array(blocks.reduce((size, b) => size + b.length, 0));
  let offset = 0;

  for (const block of blocks) {
    tar.set(block, offset);
    offset += block.length;
  }

  return tar;
};

const publishArchive = async (route: string, archive: Bun.Archive) => {
  const bytes = await archive.bytes();
  const checksum = new Bun.CryptoHasher('sha256').update(bytes).digest('hex');

  archives.set(route, { bytes, checksum });

  return checksum;
};

let server: ReturnType<typeof Bun.serve>;
let liar: Bun.TCPSocketListener;
let outputDir: string;

const url = (route: string) => `${server.url.origin}${route}`;
const outputPath = (name: string) => path.join(outputDir, name);

beforeAll(async () => {
  outputDir = await fs.mkdtemp(path.join(os.tmpdir(), 'sharkord-downloads-'));

  // Bun.serve recomputes content-length, so the header check needs a server that will send a
  // length the body does not match. anything oversized enough to be caught by the running
  // total instead would prove nothing about the header
  liar = Bun.listen({
    hostname: '127.0.0.1',
    port: 0,
    socket: {
      data(socket) {
        socket.write(
          `HTTP/1.1 200 OK\r\nContent-Length: ${MAX_DOWNLOAD_BYTES + 1}\r\n\r\n`
        );
        // left open: closing straight after the headers raced fetch, which sometimes saw the
        // socket close before it handed back the response. stop(true) in afterAll closes it
        socket.write(CHUNK.subarray(0, 16));
      }
    }
  });

  server = Bun.serve({
    port: 0,
    idleTimeout: 30,
    fetch(request) {
      const { pathname } = new URL(request.url);

      if (pathname === '/small') {
        return new Response('plugin archive bytes');
      }

      if (pathname === '/streamed-too-large') {
        return new Response(oversizedStream());
      }

      const archive = archives.get(pathname);

      if (archive) {
        return new Response(archive.bytes);
      }

      return new Response('nope', { status: 404, statusText: 'Not Found' });
    }
  });
});

afterAll(async () => {
  server.stop(true);
  liar.stop(true);
  await fs.rm(outputDir, { recursive: true, force: true });
});

describe('downloadFile', () => {
  test('should write a normal download to disk', async () => {
    const target = outputPath('small.archive');

    await downloadFile(url('/small'), target);

    expect(await Bun.file(target).text()).toBe('plugin archive bytes');
  });

  test('should refuse a download that declares a size past the cap', async () => {
    const target = outputPath('declared.archive');

    await expect(
      downloadFile(`http://127.0.0.1:${liar.port}/`, target)
    ).rejects.toThrow('Download exceeds the maximum allowed size');

    expect(await Bun.file(target).exists()).toBe(false);
  });

  // the header is the host's word for it, so the running total is the check that actually holds
  test('should refuse a download that grows past the cap without declaring it', async () => {
    const target = outputPath('streamed.archive');

    await expect(
      downloadFile(url('/streamed-too-large'), target)
    ).rejects.toThrow('Download exceeds the maximum allowed size');

    // M20's real requirement: a refused download leaves nothing behind to be picked up later
    expect(await Bun.file(target).exists()).toBe(false);
  });

  test('should refuse a download the host does not serve', async () => {
    const target = outputPath('missing.archive');

    await expect(downloadFile(url('/missing'), target)).rejects.toThrow(
      'Failed to download file: 404'
    );

    expect(await Bun.file(target).exists()).toBe(false);
  });
});

describe('downloadPlugin', () => {
  test('should install an archive whose manifest matches the requested plugin', async () => {
    const checksum = await publishArchive(
      '/plugin-good.tar',
      pluginArchive('plugin-good')
    );

    await downloadPlugin('plugin-good', url('/plugin-good.tar'), checksum);

    expect(
      await Bun.file(
        path.join(PLUGINS_PATH, 'plugin-good', 'manifest.json')
      ).exists()
    ).toBe(true);

    await fs.rm(path.join(PLUGINS_PATH, 'plugin-good'), {
      recursive: true,
      force: true
    });
  });

  // otherwise installing one plugin could overwrite a different one on disk
  test('should refuse an archive whose manifest id is not the requested plugin', async () => {
    const checksum = await publishArchive(
      '/plugin-impostor.tar',
      pluginArchive('plugin-impostor')
    );

    await expect(
      downloadPlugin('plugin-wanted', url('/plugin-impostor.tar'), checksum)
    ).rejects.toThrow(
      "Downloaded archive contains plugin 'plugin-impostor', expected 'plugin-wanted'"
    );

    expect(
      await Bun.file(
        path.join(PLUGINS_PATH, 'plugin-impostor', 'manifest.json')
      ).exists()
    ).toBe(false);
  });

  test('should refuse an archive with an entry that escapes the extraction directory', async () => {
    const checksum = await publishArchive(
      '/plugin-traversal.tar',
      pluginArchive('plugin-traversal', {
        '../escaped.txt': 'should never be written'
      })
    );

    await expect(
      downloadPlugin('plugin-traversal', url('/plugin-traversal.tar'), checksum)
    ).rejects.toThrow('outside the extraction directory');
  });

  // Bun.Archive builds regular files only, so the link has to be made on disk:
  // it is what an extracted archive carrying one would leave behind
  test('should refuse an extracted archive that carries a symlink', async () => {
    const extracted = await fs.mkdtemp(path.join(os.tmpdir(), 'symlink-'));

    await fs.mkdir(path.join(extracted, 'plugin-linky'));
    await fs.writeFile(path.join(extracted, 'plugin-linky/a.txt'), 'x');
    await fs.symlink('/etc/passwd', path.join(extracted, 'plugin-linky/link'));

    await expect(assertNoLinks(extracted)).rejects.toThrow(
      'Plugins cannot ship links'
    );

    await fs.rm(extracted, { recursive: true, force: true });
  });

  // the escape the link check exists for: a link to outside the extraction directory, then a
  // file written through it. bun drops link entries when it extracts and Bun.Archive cannot
  // write them, so this builds the tar by hand and pins that nothing lands outside. it fails
  // if a bun upgrade starts honouring links, which would make the check after extraction late
  test('should not write through a link entry when extracting', async () => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'link-escape-'));
    const outside = path.join(root, 'outside');
    const extractPath = path.join(root, 'extract');

    await Promise.all([fs.mkdir(outside), fs.mkdir(extractPath)]);

    const archive = new Bun.Archive(
      buildTar([
        { name: 'escape', type: 'symlink', linkName: '../outside' },
        { name: 'escape/evil.txt', type: 'file', content: 'pwned' }
      ])
    );

    try {
      await archive.extract(extractPath);

      expect(await fs.readdir(outside)).toEqual([]);
      await expect(assertNoLinks(extractPath)).resolves.toBeUndefined();
    } finally {
      await fs.rm(root, { recursive: true, force: true });
    }
  });

  // a plugin the server could never load must not reach the plugins directory
  test('should refuse an archive built for a different sdk version', async () => {
    const checksum = await publishArchive(
      '/plugin-old-sdk.tar',
      pluginArchive('plugin-old-sdk', {}, PLUGIN_SDK_VERSION + 1)
    );

    await expect(
      downloadPlugin('plugin-old-sdk', url('/plugin-old-sdk.tar'), checksum)
    ).rejects.toThrow('is not compatible with server SDK version');

    expect(
      await Bun.file(
        path.join(PLUGINS_PATH, 'plugin-old-sdk', 'manifest.json')
      ).exists()
    ).toBe(false);
  });

  test('should refuse an archive whose checksum does not match', async () => {
    await publishArchive(
      '/plugin-tampered.tar',
      pluginArchive('plugin-tampered')
    );

    await expect(
      downloadPlugin(
        'plugin-tampered',
        url('/plugin-tampered.tar'),
        'not-the-checksum'
      )
    ).rejects.toThrow('checksum does not match');
  });
});
