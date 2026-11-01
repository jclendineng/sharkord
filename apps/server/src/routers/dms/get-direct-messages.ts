import { z } from 'zod';
import {
  getDirectMessageConversations,
  isDirectMessageOpen
} from '../../db/queries/dms';
import { getSettings } from '../../db/queries/server';
import { invariant } from '../../utils/invariant';
import { protectedProcedure } from '../../utils/trpc';

const getDirectMessagesRoute = protectedProcedure
  .input(z.void())
  .query(async ({ ctx }) => {
    const settings = await getSettings();

    invariant(settings.directMessagesEnabled, {
      code: 'FORBIDDEN',
      message: 'Direct messages are disabled on this server'
    });

    const conversations = await getDirectMessageConversations(ctx.userId);

    // this fork's list leaves closed ones out, the join hands them all out as upstream's does
    return conversations.filter(isDirectMessageOpen);
  });

export { getDirectMessagesRoute };
