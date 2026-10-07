import type { NextConfig } from 'next'
import { defaultLocale, localeCookie, locales } from './src/i18n'

const pathWithoutLocale = `/:path((?!(?:${locales.join('|')}|_next)(?:/|$)).+)`

const nextConfig: NextConfig = {
  env: {
    // リクエストごとに描画するページ（404 など）も next start 時の環境変数ではなく、ビルドで必須にした値を使うよう埋め込む
    // https://nextjs.org/docs/app/api-reference/config/next-config-js/env
    SITE_URL: process.env.SITE_URL,
  },
  async rewrites() {
    return {
      // proxy は public のファイルより先に動くため、ドットを含むパスはロケール付きに振り分けられない。
      // ファイルの確認後に残ったロケールの無いパスを [lang] の not-found.tsx に回す
      // https://nextjs.org/docs/app/api-reference/config/next-config-js/rewrites
      afterFiles: [
        // proxy の getLocale と同じく、Cookie で選んだ言語を既定より優先する（Accept-Language の優先度による選択は rewrite の条件では書けない）
        ...locales.map((locale) => ({
          source: pathWithoutLocale,
          has: [{ type: 'cookie' as const, key: localeCookie, value: locale }],
          destination: `/${locale}/:path`,
        })),
        { source: pathWithoutLocale, destination: `/${defaultLocale}/:path` },
      ],
    }
  },
}

export default nextConfig
