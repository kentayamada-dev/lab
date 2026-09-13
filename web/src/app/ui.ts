// The classes every screen dresses its controls in. Held together here because
// the app is three screens of the same handful of widgets, and a button that
// looks different on one of them would only be a slip.

export const inputClass =
  "rounded border border-zinc-300 px-3 py-2 text-sm outline-none focus:border-zinc-500 dark:border-zinc-700 dark:focus:border-zinc-400";

export const buttonClass =
  "cursor-pointer rounded border border-zinc-300 px-3 py-2 text-sm hover:bg-zinc-100 disabled:cursor-default disabled:opacity-50 dark:border-zinc-700 dark:hover:bg-zinc-900";

// For the two buttons that close an account. Same shape, so that what marks
// them out is the colour alone.
export const dangerButtonClass = `${buttonClass} border-red-300 text-red-700 hover:bg-red-50 dark:border-red-900 dark:text-red-400 dark:hover:bg-red-950`;

export const errorClass = "text-sm text-red-700 dark:text-red-400";
