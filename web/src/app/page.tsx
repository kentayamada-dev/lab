import { Button } from '@/components/button'

export default function Page() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-between p-24">
      <h1 className="text-4xl font-bold">Welcome to Next.js!</h1>
      <Button label="Click Me" />
    </main>
  )
}
