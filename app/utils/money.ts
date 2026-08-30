/**
 * Money is stored and transported as integer minor units throughout Ledger
 * Suit. It is converted to a decimal string only at the moment it is rendered,
 * and never used in arithmetic as a floating point number.
 */

/** Minor units per major unit, by ISO 4217 exponent. Defaults to 2. */
const MINOR_UNITS: Record<string, number> = {
  BHD: 3,
  JOD: 3,
  JPY: 0,
  KWD: 3,
  OMR: 3,
  TND: 3,
}

export function minorUnitFor(currency: string): number {
  return MINOR_UNITS[currency.toUpperCase()] ?? 2
}

/**
 * Western digits are used in both locales.
 *
 * The typography guidelines allow either Western (1234) or Eastern-Arabic
 * (١٢٣٤) numerals, but require consistency within a view. Accounting tables mix
 * figures with account codes and references that stay Latin, and `tabular-nums`
 * column alignment only works within one numeral system — so Western digits win
 * for the whole product rather than per-locale.
 */
function numericLocale(locale: string): string {
  return locale.startsWith('ar') ? 'ar-EG-u-nu-latn' : locale
}

/**
 * Formats an integer minor-unit amount for display.
 *
 * `Intl.NumberFormat` takes a Number, which is why the division happens as late
 * as possible and only for presentation. Amounts beyond Number.MAX_SAFE_INTEGER
 * minor units are not representable and are reported rather than silently
 * rounded.
 */
export function formatMoney(
  amountMinor: number | bigint | string,
  currency: string,
  locale = 'en',
): string {
  const minor = BigInt(amountMinor)
  const exponent = minorUnitFor(currency)

  if (minor > BigInt(Number.MAX_SAFE_INTEGER) || minor < -BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new RangeError(`Amount ${minor} exceeds the safe display range`)
  }

  return new Intl.NumberFormat(numericLocale(locale), {
    style: 'currency',
    currency,
    minimumFractionDigits: exponent,
    maximumFractionDigits: exponent,
  }).format(Number(minor) / 10 ** exponent)
}

/** Formats a percentage for the KPI deltas. */
export function formatPercent(value: number, locale = 'en'): string {
  return new Intl.NumberFormat(numericLocale(locale), {
    style: 'percent',
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
    signDisplay: 'exceptZero',
  }).format(value / 100)
}

/** Formats an ISO date (YYYY-MM-DD) in the active locale. */
export function formatDate(iso: string | null | undefined, locale = 'en'): string {
  if (!iso) return '—'
  const date = new Date(`${iso}T00:00:00`)
  if (Number.isNaN(date.getTime())) return iso

  return new Intl.DateTimeFormat(numericLocale(locale), {
    year: 'numeric',
    month: 'short',
    day: '2-digit',
  }).format(date)
}

/** Short month label for the dashboard chart axis. */
export function formatMonth(iso: string, locale = 'en'): string {
  return new Intl.DateTimeFormat(numericLocale(locale), { month: 'short' })
    .format(new Date(iso))
}

/** Parses user input ("1,250.75") into integer minor units. */
export function parseMoneyToMinor(input: string, currency: string): bigint {
  const exponent = minorUnitFor(currency)
  // Accept Eastern-Arabic digits on input even though output is Western: a user
  // typing on an Arabic keyboard should not get a validation error.
  const normalised = input
    .replace(/[٠-٩]/g, d => String(d.charCodeAt(0) - 0x0660))
    .replace(/[۰-۹]/g, d => String(d.charCodeAt(0) - 0x06f0))
    .replace(/[٫]/g, '.')
    .replace(/[\s,٬]/g, '')

  if (!/^-?\d*(\.\d*)?$/.test(normalised) || normalised === '' || normalised === '-') {
    throw new TypeError(`"${input}" is not a valid amount`)
  }

  const negative = normalised.startsWith('-')
  const [whole = '0', fraction = ''] = normalised.replace('-', '').split('.')

  if (fraction.length > exponent) {
    throw new RangeError(`${currency} allows at most ${exponent} decimal places`)
  }

  const padded = fraction.padEnd(exponent, '0')
  const minor = BigInt(whole + padded)

  return negative ? -minor : minor
}
