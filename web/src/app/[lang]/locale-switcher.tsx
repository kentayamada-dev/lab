'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useState } from 'react'
import { type Locale, localeCookie, localeNames, locales } from '../../i18n'

export function LocaleSwitcher({ locale }: { locale: Locale }) {
  const pathname = usePathname()
  const target = locales.find((l) => l !== locale) ?? locale
  const prefix = `/${locale}`
  // next.config の rewrite で 404 に回したパスでは、usePathname がロケールの付かない元の URL を返すため
  const rest = pathname === prefix || pathname.startsWith(`${prefix}/`) ? pathname.slice(prefix.length) : pathname

  // # はサーバーで読めず、クエリも描画時に読むと useSearchParams の Suspense 境界が要るため、押す直前の URL から取り込む
  const [captured, setCaptured] = useState({ pathname, suffix: '' })
  const suffix = captured.pathname === pathname ? captured.suffix : ''
  const capture = () => {
    const { search, hash } = window.location
    setCaptured({ pathname, suffix: `${search}${hash}` })
  }
  const saveLocale = () => {
    document.cookie = `${localeCookie}=${target}; path=/; max-age=31536000; samesite=lax`
  }

  return (
    <Link
      href={`/${target}${rest}${suffix}`}
      hrefLang={target}
      lang={target}
      onPointerDown={capture}
      onKeyDown={capture}
      onClick={saveLocale}
      // auxclick は右クリックでも発火するため、新しいタブで開く中クリックに限って言語を保存する
      // https://developer.mozilla.org/en-US/docs/Web/API/Element/auxclick_event
      onAuxClick={(e) => {
        if (e.button === 1) saveLocale()
      }}
      className={[
        'inline-flex h-8 items-center rounded-md border border-gray-300 px-3 text-sm font-medium hover:bg-gray-50',
        'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600',
        'dark:border-gray-600 dark:hover:bg-gray-800 dark:focus-visible:outline-blue-400',
      ].join(' ')}
    >
      {localeNames[target]}
    </Link>
  )
}
