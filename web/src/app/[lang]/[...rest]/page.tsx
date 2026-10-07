import { notFound } from 'next/navigation'

// not-found.tsx の metadata は初回 HTML にしか使われず、ハイドレーション後は notFound() を投げたこのページの metadata に置き換わるため、同じものを出す
// https://github.com/vercel/next.js/issues/68392
export { generateMetadata } from '../not-found'

// どのルートにも一致しない URL は言語を持たない global-not-found.tsx になるため、ロケール付きのパスは残りを受けて [lang] の not-found.tsx に回す
// https://nextjs.org/docs/app/api-reference/file-conventions/not-found
export default function Page() {
  notFound()
}
