// regenerates Sharkord/Resources/emoji.json from the dataset the web client uses, so a
// shortcode resolves to the same emoji on both. run from the repo root:
//   bun apps/ios/scripts/generate-emoji.ts
import path from 'path';

const clientDir = path.resolve(import.meta.dir, '../../client');
const { gitHubEmojis } = await import(
  Bun.resolveSync('@tiptap/extension-emoji', clientDir)
);

const entries = gitHubEmojis.map(
  (e: {
    emoji?: string;
    name: string;
    shortcodes: string[];
    group?: string;
    fallbackImage?: string;
  }) => ({
    emoji: e.emoji ?? null,
    name: e.name,
    shortcodes: e.shortcodes,
    group: e.group || 'other',
    image: e.emoji ? null : (e.fallbackImage ?? null)
  })
);

const target = path.resolve(import.meta.dir, '../Sharkord/Resources/emoji.json');

await Bun.write(target, JSON.stringify(entries));

console.log(`wrote ${entries.length} emoji to ${target}`);
