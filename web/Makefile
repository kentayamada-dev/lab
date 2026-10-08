.PHONY: install dev build start storybook build-storybook preview-storybook typecheck

install:
	pnpm install

dev:
	pnpm dev

build:
	pnpm build

start:
	pnpm start

storybook:
	pnpm storybook

build-storybook:
	pnpm build-storybook

# vite preview は既定で localhost だけで待ち受け、Docker で公開したポートから届かないため、package.json で --host を付けている。
# https://vite.dev/config/preview-options#preview-host
preview-storybook:
	pnpm preview-storybook

# LayoutProps などのグローバル型は next typegen が .next/types に生成するため、先に作らないと tsc が型を見つけられず落ちる。
# https://nextjs.org/docs/app/api-reference/cli/next#next-typegen-options
typecheck:
	pnpm exec next typegen
	pnpm exec tsc --noEmit
