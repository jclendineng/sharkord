import { useTheme } from 'next-themes';
import { Toaster as Sonner, type ToasterProps } from 'sonner';

// the close button took the light theme's text colour, an invisible x on a dark toast
const TOAST_OPTIONS: ToasterProps['toastOptions'] = {
  classNames: { closeButton: 'text-inherit!' }
};

const Toaster = ({ ...props }: ToasterProps) => {
  const { theme = 'system' } = useTheme();

  return (
    <Sonner
      closeButton
      theme={theme as ToasterProps['theme']}
      className="toaster group"
      toastOptions={TOAST_OPTIONS}
      style={
        {
          '--normal-bg': 'var(--popover)',
          '--normal-text': 'var(--popover-foreground)',
          '--normal-border': 'var(--border)'
        } as React.CSSProperties
      }
      {...props}
    />
  );
};

export { Toaster };
