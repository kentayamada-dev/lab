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
    // editorconfig-checker-disable-next-line
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

  // 拡張子付きのパス（favicon.ico など public/ や app/ のメタデータファイル）はロケールを付けると404になるため振り分けない。
  // ただし先頭がロケールの大文字小文字違い（/JA/x.txt）だと、next.config の rewrite は照合で大文字小文字を区別せず拾えないため振り分ける
  // https://github.com/vercel/next.js/blob/v16.3.8/packages/next/src/shared/lib/router/utils/path-match.ts#L23
  const firstSegment = pathname.split('/')[1].toLowerCase()
  const startsWithLocaleIgnoringCase = locales.some((locale) => locale.toLowerCase() === firstSegment)
  if (pathname.includes('.') && !startsWithLocaleIgnoringCase) return

  request.nextUrl.pathname = `/${getLocale(request)}${pathname}`
  return NextResponse.redirect(request.nextUrl)
}

export const config = {
  // _next/static などの Next.js 自身のファイルはロケールを付けると壊れるため、proxy を通さない
  matcher: ['/((?!_next).*)'],
}
