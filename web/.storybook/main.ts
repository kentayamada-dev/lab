import type { StorybookConfig } from '@storybook/nextjs-vite';

const config: StorybookConfig = {
  "core": {
    "disableTelemetry": true,
  },
  "stories": [
    "../src/**/*.stories.@(ts|tsx)"
  ],
  "addons": ['@storybook/addon-themes'],
  "framework": "@storybook/nextjs-vite",
  // builder-vite は HMR の接続先を storybook dev のポートに固定するため、Docker で別のポートに公開するとブラウザが繋げない。公開側のポートを HMR_CLIENT_PORT で渡す
  // https://github.com/storybookjs/storybook/blob/v10.6.1/code/builders/builder-vite/src/vite-server.ts
  "viteFinal": (config) => {
    const clientPort = process.env.HMR_CLIENT_PORT;
    const ws = config.server?.ws;
    if (clientPort && ws !== false) {
      config.server = { ...config.server, ws: { ...ws, clientPort: Number(clientPort) } };
    }
    return config;
  },
};

export default config;
