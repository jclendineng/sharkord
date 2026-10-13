import { t } from '../../utils/trpc';
import { createPollRoute } from './create-poll';
import { endPollRoute } from './end-poll';
import { votePollRoute } from './vote-poll';

export const pollsRouter = t.router({
  create: createPollRoute,
  vote: votePollRoute,
  end: endPollRoute
});
