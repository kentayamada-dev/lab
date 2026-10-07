// proxy.ts と Client Component からも読むため、next/root-params（Server Components 専用）に依存させない
export const locales = ['ja', 'en'] as const

export type Locale = (typeof locales)[number]

export const defaultLocale: Locale = 'ja'

export const hasLocale = (locale: string): locale is Locale =>
  (locales as readonly string[]).includes(locale)

// 切り替え先の言語を読めない利用者もいるため、各言語の名前はその言語自身で書く
export const localeNames: Record<Locale, string> = {
  ja: '日本語',
  en: 'English',
}

export const localeCookie = 'locale'
