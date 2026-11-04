import { MessageNodeType } from '../statics';

const stripToText = (
  html: string,
  preProcess?: ((html: string) => string)[]
): string => {
  let result = html;

  if (preProcess) {
    for (const fn of preProcess) {
      result = fn(result);
    }
  }

  return result
    .replace(/<[^<>]*>/g, '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/\u00A0/g, ' ')
    .trim();
};

const removeProseMirrorArtifacts = (html: string): string =>
  html
    .replace(/<img(?=[^<>]*ProseMirror-separator)[^<>]*>/gi, '')
    .replace(/<br(?=[^<>]*ProseMirror-trailingBreak)[^<>]*>/gi, '');

// a line break or the end of a paragraph, list item, heading or quote is a new line in the text,
// which stripping the tags alone ran into the next line's first word. blocks closing together,
// a paragraph inside a list item, end one line
const breakLines = (html: string): string =>
  html.replace(
    /(?:<br\b[^<>]*>|<\/(?:p|li|h[1-6]|blockquote|pre|div)>)+/gi,
    '\n'
  );

const removeCommandElements = (html: string): string =>
  html.replace(/<command\b[^<>]*>.*?<\/command>/gi, '');

const emojiElementPattern = `<span(?=[^<>]*data-type="${MessageNodeType.EMOJI}")[^<>]*>`;
const channelReferenceElementPattern = `<span(?=[^<>]*data-type="${MessageNodeType.CHANNEL_REFERENCE}")[^<>]*>`;

const removeEmojiElements = (html: string): string =>
  html
    .replace(new RegExp(`${emojiElementPattern}.*?<\\/span>`, 'gi'), '')
    .replace(/<img(?=[^<>]*class="emoji-image")[^<>]*\/?>/gi, '');

const removeChannelReferenceElements = (html: string): string =>
  html.replace(
    new RegExp(`${channelReferenceElementPattern}.*?<\\/span>`, 'gi'),
    ''
  );

const hasMediaTag = (html: string): boolean =>
  /<(img|video|audio|iframe)\b/i.test(html);

const hasEmojiElement = (html: string): boolean =>
  new RegExp(emojiElementPattern).test(html) ||
  /<img(?=[^<>]*class="emoji-image")[^<>]*>/.test(html);

const hasChannelReferenceElement = (html: string): boolean =>
  new RegExp(channelReferenceElementPattern, 'i').test(html);

const isEmptyMessage = (content: string | undefined | null): boolean => {
  if (!content) return true;

  const cleaned = removeProseMirrorArtifacts(content);
  const hasMedia = hasMediaTag(cleaned);
  const hasText = stripToText(cleaned).length > 0;
  const hasChannelReference = hasChannelReferenceElement(cleaned);

  return !hasText && !hasMedia && !hasChannelReference;
};

// emoji typed straight from a phone's keyboard arrive as plain characters rather than emoji
// elements: pictographs and flags, with the joiners, variation selectors, skin tones and tags
// that build them up. digits, which also take part in keycaps, are left out
const typedEmojiPattern =
  /^(?:\p{Extended_Pictographic}|\p{Regional_Indicator}|\p{Emoji_Modifier}|[\u{E0020}-\u{E007F}]|\u200D|\uFE0F|\u20E3|\s)+$/u;

const isEmojiOnlyMessage = (content: string | undefined | null): boolean => {
  if (!content) return false;

  if (hasChannelReferenceElement(content)) return false;

  const text = stripToText(content, [removeEmojiElements]);

  if (text.length === 0) {
    return hasEmojiElement(content);
  }

  return typedEmojiPattern.test(text);
};

const getPlainTextFromHtml = (html: string): string => {
  return stripToText(html, [
    removeProseMirrorArtifacts,
    removeEmojiElements,
    removeCommandElements,
    removeChannelReferenceElements,
    breakLines
  ]);
};

export {
  getPlainTextFromHtml,
  isEmojiOnlyMessage,
  isEmptyMessage,
  removeChannelReferenceElements,
  removeCommandElements,
  removeEmojiElements
};
