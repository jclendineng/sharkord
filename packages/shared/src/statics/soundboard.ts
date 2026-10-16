// discord's bounds for a soundboard sound, the uploader and the server check the same ones
export const SOUND_NAME_MIN_LENGTH = 2;
export const SOUND_NAME_MAX_LENGTH = 32;
// with no transcoding on the server, the size is what keeps a sound short: about five to ten
// seconds, depending on the format
export const SOUND_MAX_FILE_SIZE = 512 * 1024;
// what an iphone and every browser can play as uploaded
export const SOUND_EXTENSIONS = ['.mp3', '.wav', '.m4a'];
// a percentage, so a loud clip can be turned down for everyone
export const SOUND_MIN_VOLUME = 0;
export const SOUND_MAX_VOLUME = 100;
export const SOUND_DEFAULT_VOLUME = 100;

// the sounds a server ships with, from kenney's cc0 packs (www.kenney.nl). someone who manages
// the soundboard picks which of them a server gets, a picked one is then a sound like any other
export const SOUNDBOARD_LIBRARY = [
  { key: 'you-win', name: 'You Win', emoji: '🏆' },
  { key: 'game-over', name: 'Game Over', emoji: '💀' },
  { key: 'congratulations', name: 'Congratulations', emoji: '🎉' },
  { key: 'level-up', name: 'Level Up', emoji: '⬆️' },
  { key: 'new-highscore', name: 'New Highscore', emoji: '🥇' },
  { key: 'mission-completed', name: 'Mission Completed', emoji: '✅' },
  { key: 'mission-failed', name: 'Mission Failed', emoji: '❌' },
  { key: 'final-round', name: 'Final Round', emoji: '🥊' },
  { key: 'hurry-up', name: 'Hurry Up', emoji: '⏰' },
  { key: 'fire-in-the-hole', name: 'Fire in the Hole', emoji: '💣' },
  { key: 'go-go-go', name: 'Go Go Go', emoji: '🏃' },
  { key: 'look-out', name: 'Look Out', emoji: '⚠️' },
  { key: 'medic', name: 'Medic', emoji: '🩹' },
  { key: 'correct', name: 'Correct', emoji: '👍' },
  { key: 'wrong', name: 'Wrong', emoji: '👎' },
  { key: 'laser', name: 'Laser', emoji: '🔫' },
  { key: 'explosion', name: 'Explosion', emoji: '💥' },
  { key: 'bell', name: 'Bell', emoji: '🔔' },
  { key: 'punch', name: 'Punch', emoji: '👊' },
  { key: 'dice-roll', name: 'Dice Roll', emoji: '🎲' },
  { key: 'card-shuffle', name: 'Card Shuffle', emoji: '🃏' },
  { key: 'ding', name: 'Ding', emoji: '✨' },
  { key: 'retro-jingle', name: 'Retro Jingle', emoji: '🎮' },
  { key: 'sax-jingle', name: 'Sax Jingle', emoji: '🎷' }
] as const;

export type TSoundboardLibraryKey = (typeof SOUNDBOARD_LIBRARY)[number]['key'];
