import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import { tdb } from '../../../__tests__/setup';
import { messages, settings } from '../../../db/schema';
import { processMessageMetadata } from '../get-message-metadata';
import { createOpenGraphMetadata, getDirectMediaMetaFromUrl } from '../helpers';

const insertMessage = async (content: string) => {
  const [row] = await tdb
    .insert(messages)
    .values({
      channelId: 1,
      userId: 1,
      content,
      metadata: null,
      createdAt: Date.now()
    })
    .returning();

  return row!.id;
};

const storedMetadata = async (messageId: number) => {
  const row = await tdb
    .select({ metadata: messages.metadata })
    .from(messages)
    .where(eq(messages.id, messageId))
    .get();

  return row?.metadata ?? null;
};

// a literal address is refused before anything is fetched, and a media extension resolves from
// the url alone, so both sides of this run without touching the network. what cannot be tested
// here is the dns path, which needs a hostname that really resolves into a reserved range
describe('link preview ssrf guard', () => {
  test('should refuse a link pointing straight at a private address', async () => {
    const content = 'look at http://10.0.0.1/photo.png';
    const messageId = await insertMessage(content);

    const result = await processMessageMetadata(content, messageId);

    expect(result).toBeUndefined();
    expect(await storedMetadata(messageId)).toBeNull();
  });

  test('should refuse a link pointing at the carrier grade nat range', async () => {
    const content = 'look at http://100.64.0.1/photo.png';
    const messageId = await insertMessage(content);

    const result = await processMessageMetadata(content, messageId);

    expect(result).toBeUndefined();
    expect(await storedMetadata(messageId)).toBeNull();
  });

  test('should refuse a link pointing at the cloud metadata endpoint', async () => {
    const content = 'look at http://169.254.169.254/latest/meta-data.png';
    const messageId = await insertMessage(content);

    const result = await processMessageMetadata(content, messageId);

    expect(result).toBeUndefined();
    expect(await storedMetadata(messageId)).toBeNull();
  });

  test('should preview a private address once the admin allows the server network', async () => {
    await tdb.update(settings).set({ linkPreviewsPrivateNetwork: true });

    const content = 'look at http://10.0.0.1/photo.png';
    const messageId = await insertMessage(content);

    const result = await processMessageMetadata(content, messageId);

    expect(result).toBeDefined();
    expect(await storedMetadata(messageId)).not.toBeNull();
  });

  test('should still build metadata for a routable address', async () => {
    const content = 'look at http://93.184.216.34/photo.png';
    const messageId = await insertMessage(content);

    const result = await processMessageMetadata(content, messageId);

    expect(result).toBeDefined();
    expect(await storedMetadata(messageId)).not.toBeNull();
  });
});

// a page served on the loopback address stands in for a device on the server's own network
describe('link previews of the server network', () => {
  let server: ReturnType<typeof Bun.serve>;
  let origin: string;

  beforeAll(() => {
    server = Bun.serve({
      hostname: '127.0.0.1',
      port: 0,
      fetch: (request) => {
        const { pathname } = new URL(request.url);

        if (pathname.startsWith('/moved')) {
          return Response.redirect(`${origin}/page${pathname}`, 302);
        }

        return new Response(
          '<html><head><title>Router</title><meta property="og:title" content="Home Router" /><meta property="og:description" content="Admin page" /></head></html>',
          { headers: { 'content-type': 'text/html' } }
        );
      }
    });

    origin = `http://127.0.0.1:${server.port}`;
  });

  afterAll(() => {
    server.stop(true);
  });

  test('should not preview a page on the server network by default', async () => {
    const content = `see ${origin}/page/off`;
    const messageId = await insertMessage(content);

    const result = await processMessageMetadata(content, messageId);

    expect(result).toBeUndefined();
    expect(await storedMetadata(messageId)).toBeNull();
  });

  test('should preview a page on the server network once allowed', async () => {
    await tdb.update(settings).set({ linkPreviewsPrivateNetwork: true });

    const content = `see ${origin}/page/on`;
    const messageId = await insertMessage(content);

    await processMessageMetadata(content, messageId);

    const metadata = await storedMetadata(messageId);

    expect(metadata?.[0]?.title).toBe('Home Router');
  });

  test('should follow a redirect within the server network once allowed', async () => {
    await tdb.update(settings).set({ linkPreviewsPrivateNetwork: true });

    const content = `see ${origin}/moved`;
    const messageId = await insertMessage(content);

    await processMessageMetadata(content, messageId);

    const metadata = await storedMetadata(messageId);

    expect(metadata?.[0]?.title).toBe('Home Router');
  });
});

describe('message metadata normalization', () => {
  test('normalizes link-preview-js style previews into open graph metadata', () => {
    const metadata = createOpenGraphMetadata(
      {
        title: 'Example page',
        siteName: 'Example',
        description: 'A useful preview.',
        mediaType: 'website',
        images: ['https://example.com/cover.png'],
        favicons: ['https://example.com/favicon.ico']
      },
      'https://example.com/article'
    );

    expect(metadata).toEqual({
      kind: 'open_graph',
      url: 'https://example.com/article',
      title: 'Example page',
      siteName: 'Example',
      description: 'A useful preview.',
      mediaType: 'website',
      images: ['https://example.com/cover.png'],
      videos: undefined,
      favicons: ['https://example.com/favicon.ico']
    });
  });

  test('normalizes open-graph-scraper style previews and resolves relative urls', () => {
    const metadata = createOpenGraphMetadata(
      {
        ogTitle: 'OG title',
        ogSiteName: 'OG site',
        ogDescription: 'OG description',
        ogType: 'article',
        ogImage: [{ url: '/cover.png' }],
        favicon: '/favicon.ico'
      },
      'https://example.com/posts/123'
    );

    expect(metadata).toEqual({
      kind: 'open_graph',
      url: 'https://example.com/posts/123',
      title: 'OG title',
      siteName: 'OG site',
      description: 'OG description',
      mediaType: 'article',
      images: ['https://example.com/cover.png'],
      videos: undefined,
      favicons: ['https://example.com/favicon.ico']
    });
  });

  test('skips previews without renderable open graph content', () => {
    const metadata = createOpenGraphMetadata(
      {
        mediaType: 'website'
      },
      'https://example.com/article'
    );

    expect(metadata).toBeUndefined();
  });

  test('detects direct media links from file extensions', () => {
    expect(
      getDirectMediaMetaFromUrl(new URL('https://example.com/photo.jpeg'))
    ).toEqual({
      isDirectMediaLink: true,
      mediaType: 'image'
    });

    expect(
      getDirectMediaMetaFromUrl(new URL('https://example.com/page'))
    ).toEqual({
      isDirectMediaLink: false,
      mediaType: 'none'
    });
  });
});
