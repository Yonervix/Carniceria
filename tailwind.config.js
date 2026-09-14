module.exports = {
  darkMode: ['class'],
  content: ['./src/**/*.{html,ts}'],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Geist', 'Inter', 'system-ui', '-apple-system', '"Segoe UI"', 'Roboto', 'sans-serif'],
        display: ['Geist', 'Inter', 'system-ui', '-apple-system', '"Segoe UI"', 'Roboto', 'sans-serif'],
        mono: ['"Geist Mono"', 'ui-monospace', 'SFMono-Regular', 'Menlo', 'Consolas', 'monospace'],
      },
      colors: {
        piedra: {
          50: '#f6f5f0',
          100: '#efece4',
          200: '#e2ded1',
          300: '#cec8b6',
          400: '#b2aa93',
          500: '#968d74',
          600: '#7a725e',
          700: '#625c4d',
          800: '#4f4a3f',
          900: '#423e35',
          950: '#201e19',
        },
        buey: {
          50: '#fbf1f0',
          100: '#f5dfdd',
          200: '#eac0bd',
          300: '#db9995',
          400: '#c76a66',
          500: '#ab4642',
          600: '#8f3230',
          700: '#762828',
          800: '#692222',
          900: '#5c1d1d',
          950: '#370f0f',
        },
        oliva: {
          50: '#f5f6ef',
          100: '#e9ebda',
          200: '#d6dbbc',
          300: '#bcc494',
          400: '#a2ac6e',
          500: '#87934f',
          600: '#6c7a3b',
          700: '#556236',
          800: '#464e31',
          900: '#3d442b',
          950: '#1f2415',
        },
      },
      borderRadius: {
        control: '8px',
        panel: '12px',
      },
      boxShadow: {
        premium:
          '0 1px 2px rgba(59, 57, 47, 0.05), 0 12px 32px rgba(59, 57, 47, 0.07), 0 40px 96px rgba(59, 57, 47, 0.08)',
        'premium-sm':
          '0 1px 2px rgba(59, 57, 47, 0.05), 0 6px 16px rgba(59, 57, 47, 0.06)',
        'premium-lg':
          '0 2px 4px rgba(59, 57, 47, 0.04), 0 24px 56px rgba(59, 57, 47, 0.1), 0 64px 160px rgba(59, 57, 47, 0.12)',
        hairline:
          'inset 0 1px 0 rgba(255, 255, 255, 0.6), 0 1px 2px rgba(59, 57, 47, 0.06)',
        total:
          '0 0 0 1px rgba(74, 91, 50, 0.18), 0 12px 32px rgba(74, 91, 50, 0.16)',
      },
      letterSpacing: {
        display: '-0.02em',
        label: '0.16em',
      },
      transitionTimingFunction: {
        soft: 'cubic-bezier(0.16, 1, 0.3, 1)',
      },
      zIndex: {
        nav: '40',
        overlay: '50',
        modal: '60',
      },
      maxWidth: {
        measure: '65ch',
      },
      animation: {
        'panel-in': 'panel-in 260ms cubic-bezier(0.16, 1, 0.3, 1)',
        'fade-in': 'fade-in 160ms ease-out',
      },
      keyframes: {
        'panel-in': {
          from: { opacity: '0', transform: 'translateY(12px)' },
          to: { opacity: '1', transform: 'translateY(0)' },
        },
        'fade-in': {
          from: { opacity: '0' },
          to: { opacity: '1' },
        },
      },
    },
  },
  plugins: [],
};