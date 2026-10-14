import LinkifyIt from 'linkify-it';

const linkify = new LinkifyIt();

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
