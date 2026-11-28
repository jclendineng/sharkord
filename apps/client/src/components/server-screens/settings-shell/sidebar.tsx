import { cn } from '@/lib/utils';
import { TestId } from '@sharkord/shared';
import { Input, Separator, Tooltip } from '@sharkord/ui';
import { AlertCircle } from 'lucide-react';

import { memo, useCallback, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { filterEntries } from './helpers';
import type { TSettingsEntry } from './types';

type TSidebarEntryProps = {
  entry: TSettingsEntry;
  isSelected: boolean;
  onSelect: (id: string) => void;
};

const SidebarEntry = memo(
  ({ entry, isSelected, onSelect }: TSidebarEntryProps) => {
    const { icon: Icon, logo, label, error } = entry;

    const handleClick = useCallback(
      () => onSelect(entry.id),
      [onSelect, entry.id]
    );

    return (
      <button
        data-testid={TestId.SETTINGS_SIDEBAR_ENTRY}
        onClick={handleClick}
        className={cn(
          'flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm transition-colors hover:bg-accent',
          isSelected && 'bg-accent font-medium'
        )}
      >
        {logo ? (
          <img
            src={logo}
            alt=""
            className="h-4 w-4 shrink-0 rounded-sm object-cover"
          />
        ) : (
          <Icon className="h-4 w-4 shrink-0" />
        )}
        <span className="truncate">{label}</span>
        {error && (
          <Tooltip content={error}>
            <AlertCircle
              role="img"
              aria-label={error}
              className="ml-auto h-4 w-4 shrink-0 text-destructive"
            />
          </Tooltip>
        )}
      </button>
    );
  }
);

type TSettingsSidebarProps = {
  entries: TSettingsEntry[];
  pluginEntries: TSettingsEntry[];
  selectedId: string;
  onSelect: (id: string) => void;
  className?: string;
};

const SettingsSidebar = memo(
  ({
    entries,
    pluginEntries,
    selectedId,
    onSelect,
    className
  }: TSettingsSidebarProps) => {
    const { t } = useTranslation('common');
    const [query, setQuery] = useState('');

    const shownEntries = useMemo(
      () => filterEntries(entries, query),
      [entries, query]
    );
    const shownPluginEntries = useMemo(
      () => filterEntries(pluginEntries, query),
      [pluginEntries, query]
    );

    const onQueryChange = useCallback(
      (e: React.ChangeEvent<HTMLInputElement>) => setQuery(e.target.value),
      []
    );

    return (
      <nav
        className={cn(
          'w-60 shrink-0 space-y-1 overflow-y-auto border-r bg-background p-3',
          className
        )}
      >
        <Input
          value={query}
          onChange={onQueryChange}
          placeholder={t('tableSearchPlaceholder')}
          aria-label={t('tableSearchPlaceholder')}
          className="mb-2 h-8"
        />
        {shownEntries.map((entry) => (
          <SidebarEntry
            key={entry.id}
            entry={entry}
            isSelected={entry.id === selectedId}
            onSelect={onSelect}
          />
        ))}

        {shownPluginEntries.length > 0 && (
          <>
            <Separator className="my-3" />
            {shownPluginEntries.map((entry) => (
              <SidebarEntry
                key={entry.id}
                entry={entry}
                isSelected={entry.id === selectedId}
                onSelect={onSelect}
              />
            ))}
          </>
        )}
      </nav>
    );
  }
);

export { SettingsSidebar };
