/** Load the complete chart before exposing search results or totals.
 * The configured API cap is 1,000; request smaller, deterministically ordered
 * pages. Advance by the returned size so a lower server cap also works when
 * count is available. Never return partial data after a failed page.
 */
export async function fetchAccountPages<T>(
  fetchPage: (from: number, to: number) => PromiseLike<{ data: T[] | null, error: unknown, count: number | null }>,
  signal: AbortSignal,
): Promise<T[]> {
  const rows: T[] = []
  const pageSize = 500
  while (true) {
    signal.throwIfAborted()
    const { data, error, count } = await fetchPage(rows.length, rows.length + pageSize - 1)
    signal.throwIfAborted()
    if (error) throw error
    const page = data ?? []
    rows.push(...page)
    if (count !== null ? rows.length >= count : page.length < pageSize) return rows
    if (!page.length) throw new Error('Incomplete account response')
  }
}
