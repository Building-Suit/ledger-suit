interface EdgeFunctionErrorPayload {
  error?: unknown
  message?: unknown
}

/**
 * Supabase wraps non-2xx Edge Function responses in a FunctionsHttpError.
 * Recover the function's deliberately public JSON message instead of showing
 * the wrapper's unhelpful "non-2xx status code" text to the user.
 */
export async function edgeFunctionErrorMessage(error: unknown, fallback: string): Promise<string> {
  if (typeof error === 'object' && error !== null && 'context' in error) {
    const context = (error as { context?: unknown }).context

    if (context instanceof Response) {
      try {
        const payload = await context.clone().json() as EdgeFunctionErrorPayload
        const message = payload.error ?? payload.message
        if (typeof message === 'string' && message.trim()) return message
      }
      catch {
        // The response may not be JSON. Use the safe caller-provided fallback.
      }
    }
  }

  if (error instanceof Error && !error.message.includes('non-2xx status code')) {
    return error.message
  }

  return fallback
}
