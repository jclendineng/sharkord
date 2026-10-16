import { SOUNDBOARD_LIBRARY } from '@sharkord/shared';
import { protectedProcedure } from '../../utils/trpc';

// for apps that do not share the server's code: the library this server version ships with,
// the iphone app's picker reads it from here
const getLibraryRoute = protectedProcedure.query(() => SOUNDBOARD_LIBRARY);

export { getLibraryRoute };
