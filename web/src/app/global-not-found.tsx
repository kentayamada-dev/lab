import type { Metadata } from 'next'
import Link from 'next/link'
import { ThemeProvider } from 'next-themes'
import { defaultLocale } from '../i18n'
import { titleTemplate } from '../site'
import { loadDictionary } from './[lang]/dictionaries'
import { font } from './fonts'
import './globals.css'

export async function generateMetadata(): Promise<Metadata> {
  const { notFound } = await loadDictionary(defaultLocale)
  // レイアウトを通らず title.template が掛からないため、同じ書式を自分で当てる
  return { title: titleTemplate.replace('%s', notFound.title) }
}

// レイアウトを通らずに描画されるため、html・CSS・フォント・テーマを自分で用意する
// https://nextjs.org/docs/app/api-reference/file-conventions/not-found#global-not-foundjs-experimental
export default async function GlobalNotFound() {
  const { notFound } = await loadDictionary(defaultLocale)
  return (
    // [lang]/layout.tsx と同じく、next-themes が html の class を書き換えるため
    <html lang={defaultLocale} className={font.className} suppressHydrationWarning>
      <body>
        <ThemeProvider attribute="class" disableTransitionOnChange>
          <main className="flex min-h-screen flex-col items-center justify-center gap-4 p-24">
            <h1 className="text-4xl font-bold">{notFound.title}</h1>
            {/* ロケールはこのページでは決められないため、proxy に Cookie と Accept-Language から選ばせる */}
            <Link href="/" className="text-blue-600 underline dark:text-blue-400">
              {notFound.back}
            </Link>
          </main>
        </ThemeProvider>
      </body>
    </html>
  )
}
