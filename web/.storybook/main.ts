import type { StorybookConfig } from '@storybook/nextjs-vite';

const config: StorybookConfig = {
  "core": {
    "disableTelemetry": true,
  },
  "stories": [
    "../src/**/*.stories.@(ts|tsx)"
  ],
  "addons": ['@storybook/addon-themes'],
  "framework": "@storybook/nextjs-vite"
};

export default config;
