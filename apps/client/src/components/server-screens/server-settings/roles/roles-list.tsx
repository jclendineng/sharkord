import { SettingsSection } from '@/components/server-screens/settings-shell/section';
import { getTRPCClient } from '@/lib/trpc';
import { cn } from '@/lib/utils';
import {
  closestCenter,
  DndContext,
  KeyboardSensor,
  PointerSensor,
  useSensor,
  useSensors,
  type DragEndEvent
} from '@dnd-kit/core';
import {
  arrayMove,
  SortableContext,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy
} from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import {
  getTrpcError,
  OWNER_ROLE_ID,
  type TJoinedRole
} from '@sharkord/shared';
import { IconButton, Tooltip } from '@sharkord/ui';
import { GripVertical, Plus } from 'lucide-react';
import { memo, useCallback, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';

type TRoleItemProps = {
  role: TJoinedRole;
  isSelected: boolean;
  onSelect: (roleId: number) => void;
};

const RoleItem = memo(({ role, isSelected, onSelect }: TRoleItemProps) => {
  const handleClick = useCallback(() => onSelect(role.id), [onSelect, role.id]);

  return (
    <button
      onClick={handleClick}
      className={cn(
        'flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm transition-colors hover:bg-accent',
        isSelected && 'bg-accent'
      )}
    >
      <div
        className="h-3 w-3 rounded-full"
        style={{ backgroundColor: role.color }}
      />
      <span className="truncate">{role.name}</span>
    </button>
  );
});

// a click still selects the role, only a pointer that moves a little starts a drag
const POINTER_ACTIVATION = { activationConstraint: { distance: 4 } };
const KEYBOARD_ACTIVATION = { coordinateGetter: sortableKeyboardCoordinates };

const SortableRoleItem = memo((props: TRoleItemProps) => {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging
  } = useSortable({ id: props.role.id });

  const style = useMemo(
    () => ({ transform: CSS.Transform.toString(transform), transition }),
    [transform, transition]
  );

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={cn(
        'group relative flex items-center',
        isDragging && 'z-10 opacity-80'
      )}
      {...attributes}
      {...listeners}
    >
      <GripVertical className="absolute -left-4 h-3 w-3 text-muted-foreground opacity-0 group-hover:opacity-100" />
      <RoleItem {...props} />
    </div>
  );
});

type TRolesListProps = {
  roles: TJoinedRole[];
  selectedRoleId: number | undefined;
  setSelectedRoleId: (roleId: number) => void;
  refetch: () => Promise<void>;
};

const RolesList = memo(
  ({ roles, selectedRoleId, setSelectedRoleId, refetch }: TRolesListProps) => {
    const { t } = useTranslation('settings');
    // the order just dropped, shown until the refetch brings the server's back
    const [movedIds, setMovedIds] = useState<number[]>();
    const sensors = useSensors(
      useSensor(PointerSensor, POINTER_ACTIVATION),
      useSensor(KeyboardSensor, KEYBOARD_ACTIVATION)
    );

    // the owner's role stays on top and the default one at the bottom, as discord's do
    const ownerRole = useMemo(
      () => roles.find((role) => role.id === OWNER_ROLE_ID),
      [roles]
    );
    const defaultRole = useMemo(
      () => roles.find((role) => role.isDefault),
      [roles]
    );
    const movableRoles = useMemo(() => {
      const movable = roles.filter(
        (role) => role.id !== OWNER_ROLE_ID && !role.isDefault
      );

      if (!movedIds) {
        return movable;
      }

      return [...movable].sort(
        (a, b) => movedIds.indexOf(a.id) - movedIds.indexOf(b.id)
      );
    }, [movedIds, roles]);
    const movableIds = useMemo(
      () => movableRoles.map(({ id }) => id),
      [movableRoles]
    );

    const onDragEnd = useCallback(
      async ({ active, over }: DragEndEvent) => {
        if (!over || active.id === over.id) {
          return;
        }

        const nextIds = arrayMove(
          movableIds,
          movableIds.indexOf(Number(active.id)),
          movableIds.indexOf(Number(over.id))
        );

        setMovedIds(nextIds);

        try {
          const trpc = getTRPCClient();

          await trpc.roles.reorder.mutate({ roleIds: nextIds });
          await refetch();
        } catch (error) {
          toast.error(getTrpcError(error, t('roleReorderFailed')));
        } finally {
          setMovedIds(undefined);
        }
      },
      [movableIds, refetch, t]
    );

    const onAddRole = useCallback(async () => {
      const trpc = getTRPCClient();

      try {
        const newRoleId = await trpc.roles.add.mutate();

        await refetch();

        setSelectedRoleId(newRoleId);
        toast.success(t('roleCreated'));
      } catch {
        toast.error(t('roleCreateFailed'));
      }
    }, [refetch, setSelectedRoleId, t]);

    return (
      <SettingsSection
        title={t('rolesTitle')}
        action={
          <Tooltip content={t('addRoleTooltip')}>
            <IconButton
              icon={Plus}
              aria-label={t('addRoleTooltip')}
              size="sm"
              variant="ghost"
              onClick={onAddRole}
            />
          </Tooltip>
        }
      >
        <div className="space-y-1">
          {ownerRole && (
            <RoleItem
              role={ownerRole}
              isSelected={selectedRoleId === ownerRole.id}
              onSelect={setSelectedRoleId}
            />
          )}
          <DndContext
            sensors={sensors}
            collisionDetection={closestCenter}
            onDragEnd={onDragEnd}
          >
            <SortableContext
              items={movableIds}
              strategy={verticalListSortingStrategy}
            >
              {movableRoles.map((role) => (
                <SortableRoleItem
                  key={role.id}
                  role={role}
                  isSelected={selectedRoleId === role.id}
                  onSelect={setSelectedRoleId}
                />
              ))}
            </SortableContext>
          </DndContext>
          {defaultRole && (
            <RoleItem
              role={defaultRole}
              isSelected={selectedRoleId === defaultRole.id}
              onSelect={setSelectedRoleId}
            />
          )}
        </div>
      </SettingsSection>
    );
  }
);

export { RolesList };
