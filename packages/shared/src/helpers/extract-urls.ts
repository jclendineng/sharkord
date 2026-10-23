import { LinkifyIt } from 'linkify-it';

// bare domains as links, which linkify-it 6 stopped finding by default
const linkify = new LinkifyIt({ fuzzyLink: true });

const extractUrls = (content: string): string[] => {
  try {
    const matches = linkify.match(content);

    // a bare domain gets https, as the editors link it, rather than linkify's http default
    const urls = matches
      ? matches.map((m) => (m.schema === '' ? `https://${m.raw}` : m.url))
      : [];

    // remove duplicates
    return Array.from(new Set(urls));
  } catch {
    // ignore
  }

  return [];
};

export { extractUrls };
