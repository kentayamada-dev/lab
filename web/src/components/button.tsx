import type { ComponentProps } from 'react';

const variantClasses = {
  primary: 'bg-blue-600 text-white hover:bg-blue-700 active:bg-blue-800',
  secondary: [
    'border border-gray-300 bg-white text-gray-900 hover:bg-gray-50 active:bg-gray-100',
    'dark:border-gray-600 dark:bg-gray-900 dark:text-gray-100 dark:hover:bg-gray-800 dark:active:bg-gray-700',
  ].join(' '),
} as const;

const sizeClasses = {
  sm: 'h-8 px-3 text-sm',
  md: 'h-10 px-4 text-sm',
  lg: 'h-12 px-6 text-base',
} as const;

export interface ButtonProps extends Omit<ComponentProps<'button'>, 'children'> {
  label: string;
  variant?: keyof typeof variantClasses;
  size?: keyof typeof sizeClasses;
}

export const Button = ({
  label,
  variant = 'primary',
  size = 'md',
  // フォーム内で意図せず submit されないよう、HTML の既定値 submit ではなく button にする
  type = 'button',
  className,
  ...props
}: ButtonProps) => {
  return (
    <button
      type={type}
      className={[
        'inline-flex cursor-pointer items-center justify-center rounded-md font-medium transition-colors',
        'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600',
        'dark:focus-visible:outline-blue-400',
        'disabled:pointer-events-none disabled:opacity-50',
        variantClasses[variant],
        sizeClasses[size],
        className,
      ]
        .filter(Boolean)
        .join(' ')}
      {...props}
    >
      {label}
    </button>
  );
};
