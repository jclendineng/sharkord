import { cn } from '@/lib/utils';
import { HelpCircle } from 'lucide-react';
import { memo } from 'react';
import { Label } from './label';
import { Tooltip } from './tooltip';

type TGroupProps = {
  label: string;
  children: React.ReactNode;
  description?: string;
  help?: React.ReactNode;
  required?: boolean;
  // a switch beside its label instead of under it
  inline?: boolean;
  className?: string;
};

const Group = memo(
  ({
    label,
    children,
    description,
    help,
    required,
    inline,
    className
  }: TGroupProps) => {
    let helpComponent = null;

    if (help) {
      helpComponent = (
        <Tooltip content={help}>
          <HelpCircle className="ml-1 inline-block h-3 w-3 text-muted-foreground" />
        </Tooltip>
      );
    }

    return (
      <div
        className={cn(
          inline
            ? 'flex items-center justify-between gap-6'
            : 'flex flex-col gap-2',
          className
        )}
      >
        <div className="flex min-w-0 flex-col">
          <div className="flex">
            <Label>
              {label} {required && <span className="text-red-500">*</span>}
            </Label>
            {helpComponent}
          </div>
          {description && (
            <span className="text-sm text-muted-foreground">{description}</span>
          )}
        </div>
        <div className={cn('flex gap-2', inline ? 'shrink-0' : 'flex-col')}>
          {children}
        </div>
      </div>
    );
  }
);
Group.displayName = 'Group';

export { Group };
