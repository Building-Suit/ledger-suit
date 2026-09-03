import { expect, test } from '@playwright/test'
import { edgeFunctionErrorMessage } from '../../app/utils/edgeFunctionError'

test('uses the public message returned by an Edge Function', async () => {
  const error = {
    message: 'Edge Function returned a non-2xx status code',
    context: new Response(JSON.stringify({ error: 'Billing is not configured yet.' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    }),
  }

  await expect(edgeFunctionErrorMessage(error, 'Unable to open checkout.'))
    .resolves.toBe('Billing is not configured yet.')
})

test('uses a safe fallback when the Edge Function response is not JSON', async () => {
  const error = {
    message: 'Edge Function returned a non-2xx status code',
    context: new Response('Bad gateway', { status: 502 }),
  }

  await expect(edgeFunctionErrorMessage(error, 'Unable to open checkout.'))
    .resolves.toBe('Unable to open checkout.')
})
