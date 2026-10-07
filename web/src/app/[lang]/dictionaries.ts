import { notFound } from 'next/navigation'
import { lang } from 'next/root-params'
import { hasLocale, type Locale } from '../../i18n'

const dictionaries = {
  ja: () => import('./dictionaries/ja.json').then((module) => module.default),
  en: () => import('./dictionaries/en.json').then((module) => module.default),
} satisfies Record<Locale, unknown>

export const loadDictionary = (locale: Locale) => dictionaries[locale]()

export const getDictionary = async () => {
  const locale = await lang()
  if (!hasLocale(locale)) notFound()
  return loadDictionary(locale)
}
