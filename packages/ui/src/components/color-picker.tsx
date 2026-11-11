import { PencilIcon } from 'lucide-react';
import { useCallback } from 'react';
import { HexColorPicker } from 'react-colorful';
import { cn } from '../lib/utils';
import { Button } from './button';
import { Input } from './input';
import { Popover, PopoverContent, PopoverTrigger } from './popover';

type TColorPickerProps = {
  value?: string;
  onChange?: (value: string) => void;
  error?: string;
  defaultValue?: string;
};

const ColorPicker = ({
  value,
  onChange,
  defaultValue = '#FFFFFF',
  error
}: TColorPickerProps) => {
  const onInput = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      onChange?.(e.target.value);
    },
    [onChange]
  );

  const onReset = useCallback(() => {
    onChange?.(defaultValue);
  }, [onChange, defaultValue]);

  return (
    <div className="flex flex-col">
      <Popover>
        <PopoverTrigger asChild>
          <div className="relative group cursor-pointer w-full h-32">
            <div
              style={{ backgroundColor: value }}
              className={cn(
                'w-full h-32 rounded-md border transition-opacity group-hover:opacity-70',
                error ? 'border-red-500' : 'border-border'
              )}
            />
            <div className="absolute inset-0 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity rounded-md">
              <div className="bg-black/50 rounded-full p-3">
                <PencilIcon className="h-6 w-6 text-white" />
              </div>
            </div>
          </div>
        </PopoverTrigger>
        <PopoverContent className="flex flex-col gap-2 w-fit h-fit p-2 rounded-2xl">
          <HexColorPicker color={value} onChange={onChange} />
          <Input value={value} onChange={onInput} />
          <Button size="sm" variant="ghost" onClick={onReset}>
            Reset
          </Button>
        </PopoverContent>
      </Popover>
      {error && <span className="text-sm text-red-500 mt-1">{error}</span>}
    </div>
  );
};

export { ColorPicker };
