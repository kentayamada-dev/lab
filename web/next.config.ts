import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  env: {
    // リクエストごとに描画するページ（404 など）も next start 時の環境変数ではなく、ビルドで必須にした値を使うよう埋め込む
    // https://nextjs.org/docs/app/api-reference/config/next-config-js/env
    SITE_URL: process.env.SITE_URL,
  },
  experimental: {
    // ルートレイアウトが app/[lang] にあり、どのルートにも一致しない URL を受ける app/not-found.tsx を置けないため
    // https://nextjs.org/docs/app/api-reference/file-conventions/not-found#global-not-foundjs-experimental
    globalNotFound: true,
  },
}

export default nextConfig
