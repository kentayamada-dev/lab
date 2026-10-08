'use client'

import { useTheme } from 'next-themes'
import { useEffect, useState } from 'react'

const themes = ['system', 'light', 'dark'] as const

type Theme = (typeof themes)[number]

export function ThemeSwitcher({ label, names }: { label: string; names: Record<Theme, string> }) {
  const { theme, setTheme } = useTheme()
  const [mounted, setMounted] = useState(false)

  // サーバーでは保存済みのテーマを知れず theme が undefined になり、ハイドレーションで不一致になるため、マウント後に描画する
  // https://github.com/pacocoursey/next-themes#avoid-hydration-mismatch
  useEffect(() => setMounted(true), [])

  return (
    <select
      aria-label={label}
      value={mounted && theme ? theme : 'system'}
      disabled={!mounted}
      onChange={(e) => setTheme(e.target.value)}
      className={[
        'h-8 cursor-pointer rounded-md border border-gray-300 bg-white px-2 text-sm font-medium hover:bg-gray-50',
        'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600',
        'dark:border-gray-600 dark:bg-gray-950 dark:hover:bg-gray-800 dark:focus-visible:outline-blue-400',
        'disabled:cursor-default',
      ].join(' ')}
    >
      {themes.map((t) => (
        <option key={t} value={t}>
          {names[t]}
        </option>
      ))}
    </select>
  )
}
