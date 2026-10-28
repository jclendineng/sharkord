import {
  getLocalStorageItem,
  LocalStorageKey,
  setLocalStorageItem
} from '@/helpers/storage';
import { createContext, useEffect, useState } from 'react';

type Theme = 'dark' | 'light' | 'system';

// safari's bars take theme-color, so they match the page's background in the theme picked here
// rather than the system's. the same two colors are --background in index.css
const THEME_COLORS = {
  light: '#ffffff',
  dark: '#0a0a0a'
};

type ThemeProviderProps = {
  children: React.ReactNode;
  defaultTheme?: Theme;
  storageKey?: LocalStorageKey;
};

type ThemeProviderState = {
  theme: Theme;
  setTheme: (theme: Theme) => void;
};

const initialState: ThemeProviderState = {
  theme: 'system',
  setTheme: () => null
};

const ThemeProviderContext = createContext<ThemeProviderState>(initialState);

function ThemeProvider({
  children,
  defaultTheme = 'system',
  storageKey = LocalStorageKey.VITE_UI_THEME,
  ...props
}: ThemeProviderProps) {
  const [theme, setTheme] = useState<Theme>(
    () => (getLocalStorageItem(storageKey) as Theme) || defaultTheme
  );

  useEffect(() => {
    const root = window.document.documentElement;

    root.classList.remove('light', 'dark');

    let resolvedTheme: 'dark' | 'light';

    if (theme === 'system') {
      resolvedTheme = window.matchMedia('(prefers-color-scheme: dark)').matches
        ? 'dark'
        : 'light';
    } else {
      resolvedTheme = theme;
    }

    root.classList.add(resolvedTheme);

    const themeColorMetas = document.querySelectorAll(
      'meta[name="theme-color"]'
    );

    themeColorMetas.forEach((meta) => {
      meta.setAttribute('content', THEME_COLORS[resolvedTheme]);
    });
  }, [theme]);

  const value = {
    theme,
    setTheme: (theme: Theme) => {
      setLocalStorageItem(storageKey, theme);
      setTheme(theme);
    }
  };

  return (
    <ThemeProviderContext.Provider {...props} value={value}>
      {children}
    </ThemeProviderContext.Provider>
  );
}

export { ThemeProvider };
