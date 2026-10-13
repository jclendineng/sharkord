import { getStickers } from '../../db/queries/stickers';
import { protectedProcedure } from '../../utils/trpc';

// every member sees the server's stickers, they all can send them
const getStickersRoute = protectedProcedure.query(async () => getStickers());

export { getStickersRoute };
