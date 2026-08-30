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

  return new Intl.NumberFormat(locale, {
    style: 'currency',
    currency,
    minimumFractionDigits: exponent,
    maximumFractionDigits: exponent,
  }).format(Number(minor) / 10 ** exponent)
}

/** Parses user input ("1,250.75") into integer minor units. */
export function parseMoneyToMinor(input: string, currency: string): bigint {
  const exponent = minorUnitFor(currency)
  const cleaned = input.replace(/[\s,]/g, '')

  if (!/^-?\d*(\.\d*)?$/.test(cleaned) || cleaned === '' || cleaned === '-') {
    throw new TypeError(`"${input}" is not a valid amount`)
  }

  const negative = cleaned.startsWith('-')
  const [whole = '0', fraction = ''] = cleaned.replace('-', '').split('.')

  if (fraction.length > exponent) {
    throw new RangeError(`${currency} allows at most ${exponent} decimal places`)
  }

  const padded = fraction.padEnd(exponent, '0')
  const minor = BigInt(whole + padded)

  return negative ? -minor : minor
}
