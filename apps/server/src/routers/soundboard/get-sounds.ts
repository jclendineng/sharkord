import { getSounds } from '../../db/queries/soundboard-sounds';
import { protectedProcedure } from '../../utils/trpc';

// every member sees the server's sounds: they hear them in calls even without playing them
const getSoundsRoute = protectedProcedure.query(async () => getSounds());

export { getSoundsRoute };
