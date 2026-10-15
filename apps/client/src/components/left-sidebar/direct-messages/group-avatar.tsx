import { cn } from '@/lib/utils';
import { Users } from 'lucide-react';
import { memo } from 'react';

type TGroupAvatarProps = {
  className?: string;
};

// a group conversation has no one person to show
const GroupAvatar = memo(({ className }: TGroupAvatarProps) => (
  <div
    className={cn(
      'flex shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground',
      className
    )}
  >
    <Users className="h-3.5 w-3.5" />
  </div>
));

export { GroupAvatar };
