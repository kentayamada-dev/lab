import type { Metadata } from 'next'
import Image from 'next/image'
import { Button } from '@/components/button'
import { locales } from '../../i18n'
import { getDictionary } from './dictionaries'

// layout に置くと配下の全ページが同じ代替 URL を受け継ぐため、hreflang はページごとに書く
export const metadata: Metadata = {
  alternates: {
    languages: {
      ...Object.fromEntries(locales.map((locale) => [locale, `/${locale}`])),
      // ロケールの無い / は proxy が Cookie と Accept-Language で振り分けるため、言語を選ばない入口として示す
      'x-default': '/',
    },
  },
}

export default async function Page() {
  const dict = await getDictionary()
  return (
    <main className="flex min-h-screen flex-col items-center justify-between p-24">
      <Image
        className="dark:invert h-auto w-[100px]"
        src="/next.svg"
        alt="Next.js logo"
        width={100}
        height={20}
      />
      <h1 className="text-4xl font-bold">{dict.home.title}</h1>
      <Button label={dict.home.button} />
    </main>
  )
}
