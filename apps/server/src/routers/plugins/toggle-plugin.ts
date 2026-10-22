import { ActivityLogType, Permission, zPluginId } from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { publishCapabilityAccess } from '../../db/publishers';
import { pluginManager } from '../../plugins';
import { enqueueActivityLog } from '../../queues/activity-log';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const togglePluginRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.pluginManage.maxRequests,
  windowMs: config.rateLimiters.pluginManage.windowMs,
  logLabel: 'togglePlugin'
})
  .input(
    z.object({
      pluginId: zPluginId,
      enabled: z.boolean()
    })
  )
  .mutation(async ({ ctx, input }) => {
    await ctx.needsPermission(Permission.MANAGE_PLUGINS);

    await pluginManager.togglePlugin(input.pluginId, input.enabled);

    pluginManager.publishPlugins();
    publishCapabilityAccess();

    enqueueActivityLog({
      type: ActivityLogType.PLUGIN_TOGGLED,
      userId: ctx.user.id,
      details: {
        pluginId: input.pluginId,
        enabled: input.enabled
      }
    });
  });

export { togglePluginRoute };
