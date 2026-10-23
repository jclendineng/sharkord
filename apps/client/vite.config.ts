import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react-swc';
import path from 'path';
import { defineConfig, loadEnv } from 'vite';
import pkg from './package.json' with { type: 'json' };

// https://vite.dev/config/
export default defineConfig(({ command, mode }) => {
  const env = loadEnv(mode, process.cwd(), '');

  return {
    // relative in the build, so the same files work at the root and under a proxy's subpath
    base: command === 'build' ? './' : '/',
    plugins: [react(), tailwindcss()],
    build: {
      target: 'esnext'
    },
    resolve: {
      alias: {
        '@': path.resolve(import.meta.dirname, './src')
      }
    },
    define: {
      VITE_APP_VERSION: JSON.stringify(pkg.version)
    },
    server: {
      proxy: {
        '/manifest.json': `http://localhost:${env.SERVER_PORT || 4991}`,
        // sanitizing rewrites message image urls to same-origin paths, which in dev is
        // this vite server rather than the one holding the files
        '/public': `http://localhost:${env.SERVER_PORT || 4991}`
      }
    }
  };
});
