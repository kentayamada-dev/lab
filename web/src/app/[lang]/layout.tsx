import type { Metadata } from 'next'
import { notFound } from 'next/navigation'
import { lang } from 'next/root-params'
import { ThemeProvider } from 'next-themes'
import { hasLocale, locales } from '../../i18n'
import { siteName, siteUrl, titleTemplate } from '../../site'
import { font } from '../fonts'
import '../globals.css'
import { getDictionary } from './dictionaries'
import { LocaleSwitcher } from './locale-switcher'
import { ThemeSwitcher } from './theme-switcher'

export async function generateStaticParams() {
  return locales.map((locale) => ({ lang: locale }))
}

// 未知のロケールが下の notFound() に届くと Next.js 既定の 404 になるため、ルート不一致として global-not-found.tsx に回す
export const dynamicParams = false

export async function generateMetadata(): Promise<Metadata> {
  const { metadata } = await getDictionary()
  return {
    metadataBase: siteUrl,
    title: { template: titleTemplate, default: siteName },
    description: metadata.description,
  }
}

export default async function Layout({ children }: LayoutProps<'/[lang]'>) {
  const locale = await lang()
  if (!hasLocale(locale)) notFound()
  const { theme } = await getDictionary()

  return (
    // next-themes がハイドレーション前に html の class を書き換えるため、html 自身の不一致警告だけを抑える
    // https://github.com/pacocoursey/next-themes#with-app
    <html lang={locale} className={font.className} suppressHydrationWarning>
      <body>
        <ThemeProvider attribute="class" disableTransitionOnChange>
          <header className="fixed top-4 right-4 flex gap-2">
            <ThemeSwitcher label={theme.label} names={theme} />
            <LocaleSwitcher locale={locale} />
          </header>
          {children}
        </ThemeProvider>
      </body>
    </html>
  )
}
