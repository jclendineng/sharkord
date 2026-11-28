import { SettingsSection } from '@/components/server-screens/settings-shell/section';
import { openServerScreen } from '@/features/server-screens/actions';
import { useCategories } from '@/features/server/categories/hooks';
import { useChannelsByCategoryId } from '@/features/server/channels/hooks';
import { useCan } from '@/features/server/hooks';
import { ChannelType, Permission } from '@sharkord/shared';
import { Button } from '@sharkord/ui';
import { Hash, Volume2 } from 'lucide-react';
import { memo, useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import { ServerScreen } from '../../screens';

type TChannelRowProps = {
  channelId: number;
  name: string;
  isVoice: boolean;
};

const ChannelRow = memo(({ channelId, name, isVoice }: TChannelRowProps) => {
  const { t } = useTranslation('sidebar');
  const Icon = isVoice ? Volume2 : Hash;

  const onEditClick = useCallback(() => {
    openServerScreen(ServerScreen.CHANNEL_SETTINGS, { channelId });
  }, [channelId]);

  return (
    <div className="flex items-center gap-2 py-1.5 text-sm">
      <Icon className="h-4 w-4 text-muted-foreground" />
      <span className="flex-1 truncate">{name}</span>
      <Button variant="ghost" size="sm" onClick={onEditClick}>
        {t('editLabel')}
      </Button>
    </div>
  );
});

type TCategoryBlockProps = {
  categoryId: number;
  name: string;
  canManageCategories: boolean;
};

const CategoryBlock = memo(
  ({ categoryId, name, canManageCategories }: TCategoryBlockProps) => {
    const { t } = useTranslation('sidebar');
    const channels = useChannelsByCategoryId(categoryId);

    const onEditClick = useCallback(() => {
      openServerScreen(ServerScreen.CATEGORY_SETTINGS, { categoryId });
    }, [categoryId]);

    return (
      <div>
        <div className="flex items-center gap-2 border-b border-border pb-1">
          <span className="flex-1 text-xs font-semibold uppercase text-muted-foreground">
            {name}
          </span>
          {canManageCategories && (
            <Button variant="ghost" size="sm" onClick={onEditClick}>
              {t('editLabel')}
            </Button>
          )}
        </div>
        {channels.map((channel) => (
          <ChannelRow
            key={channel.id}
            channelId={channel.id}
            name={channel.name}
            isVoice={channel.type === ChannelType.VOICE}
          />
        ))}
      </div>
    );
  }
);

// the apps' Channels page: every category and channel in order, each opening its own settings.
// creating, moving and deleting stay in the sidebar, where they already are on the web
const Channels = memo(() => {
  const { t } = useTranslation('settings');
  const categories = useCategories();
  const can = useCan();
  const canManageCategories = can(Permission.MANAGE_CATEGORIES);

  return (
    <SettingsSection title={t('channelsTab')} description={t('channelsDesc')}>
      {categories.map((category) => (
        <CategoryBlock
          key={category.id}
          categoryId={category.id}
          name={category.name}
          canManageCategories={canManageCategories}
        />
      ))}
    </SettingsSection>
  );
});

export { Channels };
