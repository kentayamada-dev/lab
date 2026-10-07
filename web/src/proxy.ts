import { match } from '@formatjs/intl-localematcher'
import Negotiator from 'negotiator'
import { type NextRequest, NextResponse } from 'next/server'
import { defaultLocale, hasLocale, localeCookie, locales } from './i18n'

function getLocale(request: NextRequest) {
  const saved = request.cookies.get(localeCookie)?.value
  if (saved && hasLocale(saved)) return saved

  const headers = { 'accept-language': request.headers.get('accept-language') ?? '' }
  const languages = new Negotiator({ headers }).languages()
  try {
    return match(languages, locales, defaultLocale)
  } catch {
    // `*` や不正な言語タグで match が RangeError を投げる（内部の Intl.getCanonicalLocales）ため、既定のロケールに倒す
    // https://github.com/formatjs/formatjs/blob/@formatjs/intl-localematcher@0.9.0/packages/intl-localematcher/abstract/CanonicalizeLocaleList.ts
    return defaultLocale
  }
}

export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl
  const pathnameHasLocale = locales.some(
    (locale) => pathname.startsWith(`/${locale}/`) || pathname === `/${locale}`,
  )

  if (pathnameHasLocale) return

  request.nextUrl.pathname = `/${getLocale(request)}${pathname}`
  return NextResponse.redirect(request.nextUrl)
}

export const config = {
  // 拡張子付きのパス（favicon.ico など public/ や app/ のメタデータファイル）はロケールを付けると404になるため振り分けない
  matcher: ['/((?!_next|.*\\..*).*)'],
}
