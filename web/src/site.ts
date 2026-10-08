export const siteName = 'Next.js App'

export const titleTemplate = `%s | ${siteName}`

// hreflang などの絶対 URL の基点。localhost の URL を公開しないよう既定値を持たず、未設定なら止める。
// next dev は .env.development を、next start は next.config の env で埋め込んだビルド時の値を読む
if (!process.env.SITE_URL) {
  throw new Error(
    'SITE_URL が未設定です。next dev は web/.env.development から読み、make build では公開先の URL（例: https://example.com）を渡します',
  )
}

export const siteUrl = new URL(process.env.SITE_URL)
