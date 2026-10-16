import type { TSoundboardLibraryKey } from '@sharkord/shared';
import bell from '../soundboard-library/bell.m4a' with { type: 'file' };
import cardShuffle from '../soundboard-library/card-shuffle.m4a' with { type: 'file' };
import congratulations from '../soundboard-library/congratulations.m4a' with { type: 'file' };
import correct from '../soundboard-library/correct.m4a' with { type: 'file' };
import diceRoll from '../soundboard-library/dice-roll.m4a' with { type: 'file' };
import ding from '../soundboard-library/ding.m4a' with { type: 'file' };
import explosion from '../soundboard-library/explosion.m4a' with { type: 'file' };
import finalRound from '../soundboard-library/final-round.m4a' with { type: 'file' };
import fireInTheHole from '../soundboard-library/fire-in-the-hole.m4a' with { type: 'file' };
import gameOver from '../soundboard-library/game-over.m4a' with { type: 'file' };
import goGoGo from '../soundboard-library/go-go-go.m4a' with { type: 'file' };
import hurryUp from '../soundboard-library/hurry-up.m4a' with { type: 'file' };
import laser from '../soundboard-library/laser.m4a' with { type: 'file' };
import levelUp from '../soundboard-library/level-up.m4a' with { type: 'file' };
import lookOut from '../soundboard-library/look-out.m4a' with { type: 'file' };
import medic from '../soundboard-library/medic.m4a' with { type: 'file' };
import missionCompleted from '../soundboard-library/mission-completed.m4a' with { type: 'file' };
import missionFailed from '../soundboard-library/mission-failed.m4a' with { type: 'file' };
import newHighscore from '../soundboard-library/new-highscore.m4a' with { type: 'file' };
import punch from '../soundboard-library/punch.m4a' with { type: 'file' };
import retroJingle from '../soundboard-library/retro-jingle.m4a' with { type: 'file' };
import saxJingle from '../soundboard-library/sax-jingle.m4a' with { type: 'file' };
import wrong from '../soundboard-library/wrong.m4a' with { type: 'file' };
import youWin from '../soundboard-library/you-win.m4a' with { type: 'file' };

// the library's audio, embedded in the compiled server by the file imports, so a self hosted
// server has it with nothing to download. a path to read with Bun.file in dev and in the binary
const SOUNDBOARD_LIBRARY_FILES: Record<TSoundboardLibraryKey, string> = {
  'you-win': youWin,
  'game-over': gameOver,
  congratulations: congratulations,
  'level-up': levelUp,
  'new-highscore': newHighscore,
  'mission-completed': missionCompleted,
  'mission-failed': missionFailed,
  'final-round': finalRound,
  'hurry-up': hurryUp,
  'fire-in-the-hole': fireInTheHole,
  'go-go-go': goGoGo,
  'look-out': lookOut,
  medic: medic,
  correct: correct,
  wrong: wrong,
  laser: laser,
  explosion: explosion,
  bell: bell,
  punch: punch,
  'dice-roll': diceRoll,
  'card-shuffle': cardShuffle,
  ding: ding,
  'retro-jingle': retroJingle,
  'sax-jingle': saxJingle
};

const getSoundboardLibraryFile = (key: TSoundboardLibraryKey) =>
  SOUNDBOARD_LIBRARY_FILES[key];

export { getSoundboardLibraryFile };
