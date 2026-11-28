// one choice over the two stored flags: all wins over mentions, so they never both apply
export type TMessageLevel = 'all' | 'mentions' | 'off';

export const toMessageLevel = (
  all: boolean,
  mentions: boolean
): TMessageLevel => {
  if (all) {
    return 'all';
  }

  if (mentions) {
    return 'mentions';
  }

  return 'off';
};

export const fromMessageLevel = (level: TMessageLevel) => ({
  all: level === 'all',
  mentions: level === 'mentions'
});
