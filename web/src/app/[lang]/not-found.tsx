import type { Metadata } from 'next'
import Link from 'next/link'
import { lang } from 'next/root-params'
import { getDictionary } from './dictionaries'

export async function generateMetadata(): Promise<Metadata> {
  const { notFound } = await getDictionary()
  return { title: notFound.title }
}

export default async function NotFound() {
  const { notFound } = await getDictionary()
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-4 p-24">
      <h1 className="text-4xl font-bold">{notFound.title}</h1>
      <Link href={`/${await lang()}`} className="text-blue-600 underline dark:text-blue-400">
        {notFound.back}
      </Link>
    </main>
  )
}
