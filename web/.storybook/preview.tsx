import type { Preview } from '@storybook/nextjs-vite'
import { withThemeByClassName } from '@storybook/addon-themes';
import { font } from "../src/app/fonts"
import "../src/app/globals.css"

// Storybook は app/[lang]/layout.tsx を描画しないため、layout と同じく html にフォントの class を付ける
document.documentElement.classList.add(font.className)

const preview: Preview = {
  parameters: {
    controls: {
      matchers: {
        color: /(background|color)$/i,
        date: /Date$/i,
      },
    },
  },
};

export const decorators = [
  withThemeByClassName({
    themes: {
      light: 'light',
      dark: 'dark',
    },
    defaultTheme: 'light',
  }),
];

export default preview;
