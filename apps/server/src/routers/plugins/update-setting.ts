import { ActivityLogType, Permission, zPluginId } from '@sharkord/shared';
import z from 'zod';
import { config } from '../../config';
import { pluginManager } from '../../plugins';
import { enqueueActivityLog } from '../../queues/activity-log';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const updateSettingRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.pluginManage.maxRequests,
  windowMs: config.rateLimiters.pluginManage.windowMs,
  logLabel: 'updatePluginSetting'
})
  .input(
    z.object({
      pluginId: zPluginId,
      key: z.string(),
      value: z.union([z.string(), z.number(), z.boolean()])
    })
  )
  .mutation(async ({ ctx, input }) => {
    await ctx.needsPermission(Permission.MANAGE_PLUGINS);

    await pluginManager.updatePluginSetting(
      input.pluginId,
      input.key,
      input.value
    );

    enqueueActivityLog({
      type: ActivityLogType.PLUGIN_SETTING_UPDATED,
      userId: ctx.user.id,
      details: { pluginId: input.pluginId, key: input.key }
    });
  });

export { updateSettingRoute };
