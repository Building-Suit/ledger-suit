export interface ParsedCsv {
  headers: string[]
  rows: Record<string, string>[]
}

/** Parse RFC 4180-style CSV, including quoted commas, quotes, and newlines. */
export function parseCsv(text: string): ParsedCsv {
  const records: string[][] = []
  let record: string[] = []
  let field = ''
  let quoted = false

  const source = text.replace(/^\uFEFF/, '')
  for (let index = 0; index < source.length; index++) {
    const character = source[index]!
    if (quoted) {
      if (character === '"' && source[index + 1] === '"') {
        field += '"'
        index++
      }
      else if (character === '"') quoted = false
      else field += character
      continue
    }

    if (character === '"' && field === '') quoted = true
    else if (character === ',') {
      record.push(field)
      field = ''
    }
    else if (character === '\n' || character === '\r') {
      if (character === '\r' && source[index + 1] === '\n') index++
      record.push(field)
      if (record.some(value => value !== '')) records.push(record)
      record = []
      field = ''
    }
    else field += character
  }

  if (quoted) throw new Error('CSV_UNCLOSED_QUOTE')
  record.push(field)
  if (record.some(value => value !== '')) records.push(record)
  if (records.length < 2) throw new Error('CSV_NO_DATA')

  const headers = records[0]!.map(value => value.trim())
  if (headers.some(header => !header) || new Set(headers).size !== headers.length) {
    throw new Error('CSV_HEADERS_INVALID')
  }

  const rows = records.slice(1).map((values) => {
    if (values.length > headers.length) throw new Error('CSV_ROW_WIDTH_INVALID')
    return Object.fromEntries(headers.map((header, index) => [header, values[index] ?? '']))
  })
  return { headers, rows }
}
