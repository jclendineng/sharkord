import { DEFAULT_PROFILE_COLOR } from '../types';

// the golden angle spreads neighbouring ids far apart on the color wheel, so people who joined
// one after the other still look different
const GOLDEN_ANGLE = 137.508;

// the two ends of the gradient an avatar without a picture is drawn with. a profile color the
// user picked wins, everyone else gets a hue from their id. mirrored in the app's AvatarView
export const getAvatarGradient = (
  userId: number,
  profileColor?: string | null
): { from: string; to: string } => {
  if (profileColor && profileColor !== DEFAULT_PROFILE_COLOR) {
    return { from: profileColor, to: profileColor };
  }

  const hue = Math.round((userId * GOLDEN_ANGLE) % 360);

  return {
    from: `hsl(${hue}, 60%, 52%)`,
    to: `hsl(${(hue + 40) % 360}, 65%, 38%)`
  };
};
