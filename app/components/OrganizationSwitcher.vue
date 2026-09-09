<script setup lang="ts">
import type { Database } from '~~/types/database.types'

const supabase = useSupabaseClient<Database>()
const { organizations, current, setOrganization, loadOrganizations, roleLabel } = useTenant()
const { checkoutRequired, createCheckoutSession, load: loadBilling } = useBilling()
const { t } = useI18n()
const route = useRoute()
const describeError = useErrorMessage()

const open = ref(false)
const root = ref<HTMLElement | null>(null)
const createOpen = ref(false)
const name = ref('')
const legalName = ref('')
const currency = ref('EGP')
const interval = ref<'monthly' | 'yearly'>('monthly')
const pending = ref(false)
const errorMessage = ref('')
const pendingOrganizationId = ref<string | null>(null)

useClickOutside(root, () => (open.value = false))

async function choose(id: string) {
  open.value = false
  await setOrganization(id)
  await loadBilling()
  if (checkoutRequired.value) await navigateTo('/subscribe')
  else if (route.path === '/subscribe') await navigateTo('/dashboard')
}

function showCreate() {
  open.value = false
  createOpen.value = true
  name.value = ''
  legalName.value = ''
  currency.value = current.value?.base_currency ?? 'EGP'
  interval.value = 'monthly'
  pendingOrganizationId.value = null
  errorMessage.value = ''
}

function closeCreate() {
  if (!pending.value) createOpen.value = false
}

async function createAndCheckout() {
  pending.value = true
  errorMessage.value = ''
  try {
    if (!pendingOrganizationId.value) {
      const normalizedName = name.value.trim()
      const normalizedLegalName = legalName.value.trim()
      if (!normalizedName || !normalizedLegalName) {
        errorMessage.value = t('onboarding.completeRequired')
        return
      }

      // This gives immediate feedback. The unique index inside
      // create_organization remains the authoritative race-safe check.
      const { data: isAvailable, error: availabilityError } = await supabase.rpc('check_legal_name_availability', {
        p_legal_name: normalizedLegalName,
      })
      if (availabilityError) throw availabilityError
      if (!isAvailable) {
        errorMessage.value = t('onboarding.legalNameTaken')
        return
      }

      const { data, error } = await supabase.rpc('create_organization', {
        p_name: normalizedName,
        p_legal_name: normalizedLegalName,
        p_base_currency: currency.value,
      })
      if (error) throw error
      pendingOrganizationId.value = data
      // Keep the paid workspace selected while Checkout is being prepared. If
      // Stripe is temporarily unavailable, the locked workspace is still in
      // the switcher and this dialog can retry without creating a duplicate.
      await loadOrganizations(undefined, { force: true })
    }

    const organizationId = pendingOrganizationId.value
    if (!organizationId) throw new Error(t('billing.checkoutFailed'))
    const url = await createCheckoutSession(organizationId, interval.value, t('billing.checkoutFailed'))
    await setOrganization(organizationId)
    window.location.assign(url)
  }
  catch (error) {
    errorMessage.value = describeError(error)
  }
  finally {
    pending.value = false
  }
}

function onEscape(event: KeyboardEvent) {
  if (event.key === 'Escape' && createOpen.value) closeCreate()
}

onMounted(() => window.addEventListener('keydown', onEscape))
onBeforeUnmount(() => window.removeEventListener('keydown', onEscape))
</script>

<template>
  <div ref="root" class="relative">
    <button
      type="button"
      class="ls-btn w-full justify-between"
      :aria-expanded="open"
      aria-haspopup="listbox"
      :aria-label="t('org.switcher')"
      @click="open = !open"
    >
      <span class="flex flex-col min-w-0 text-start">
        <span class="truncate">{{ current?.name ?? t('org.none') }}</span>
        <span v-if="current?.legal_name" class="truncate text-[10px] text-fg-muted">{{ current.legal_name }}</span>
      </span>
      <AppIcon name="arrowDown" class="text-fg-muted -me-3" />
    </button>

    <ul
      v-if="open"
      class="ls-card absolute z-30 mt-1 w-full overflow-hidden p-1 shadow-overlay"
      role="listbox"
    >
      <li v-for="org in organizations" :key="org.id">
        <button
          type="button"
          role="option"
          :aria-selected="org.id === current?.id"
          class="flex w-full items-center justify-between gap-2 rounded-chip px-2 py-2 text-start text-sm hover:bg-surface-muted"
          @click="choose(org.id)"
        >
          <span class="min-w-0">
            <span class="block truncate">{{ org.name }}</span>
            <span v-if="org.legal_name" class="block truncate text-[10px] text-fg-muted">{{ org.legal_name }}</span>
            <span class="block text-xs text-fg-muted">
              {{ roleLabel(org.role, org.role_id) }} · {{ org.base_currency }}
            </span>

            <StatusBadge :status="org.status === 'trial' ? 'trialing' : 'active'" />
          </span>
          <AppIcon v-if="org.id === current?.id" name="check" class="text-[var(--bs-status-success)]" />
        </button>
      </li>
      <li class="mt-1 border-t border-[var(--bs-border)] pt-1">
        <button
          type="button"
          class="flex w-full items-center gap-2 rounded-chip px-2 py-2 text-start text-sm font-semibold text-accent hover:bg-surface-muted"
          @click="showCreate"
        >
          <AppIcon name="add" :size="18" />
          <span>{{ t('org.createAnother') }}</span>
        </button>
      </li>
    </ul>

    <Teleport to="body">
      <Transition name="ls-modal">
        <div
          v-if="createOpen"
          class="fixed inset-0 z-[80] grid place-items-center ls-scrim p-4"
          role="dialog"
          aria-modal="true"
          aria-labelledby="create-organization-title"
          @click.self="closeCreate"
        >
          <form class="ls-modal-panel ls-card w-full max-w-lg space-y-5 p-6 shadow-overlay" @submit.prevent="createAndCheckout">
            <div class="flex items-start justify-between gap-4">
              <div>
                <p class="text-sm font-semibold text-accent">{{ t('org.additionalEyebrow') }}</p>
                <h2 id="create-organization-title" class="mt-1 text-xl font-bold">{{ t('org.createAnother') }}</h2>
                <p class="mt-2 text-sm text-fg-muted">{{ t('org.additionalBillingHint') }}</p>
              </div>
              <button type="button" class="ls-btn ls-btn-sm shrink-0" :aria-label="t('common.close')" :disabled="pending" @click="closeCreate">
                <AppIcon name="close" />
              </button>
            </div>

            <FloatingField :label="t('org.name')">
              <input id="additional-org-name" v-model="name" class="ls-input" required :disabled="Boolean(pendingOrganizationId)">
            </FloatingField>

            <FloatingField :label="t('onboarding.legalName')">
              <input id="additional-org-legal-name" v-model="legalName" class="ls-input" required :disabled="Boolean(pendingOrganizationId)">
            </FloatingField>

            <FloatingField :label="t('accounts.currency')">
              <select id="additional-org-currency" v-model="currency" class="ls-input" :disabled="Boolean(pendingOrganizationId)">
                <option v-for="code in ['EGP', 'USD', 'EUR', 'GBP', 'SAR', 'AED']" :key="code">{{ code }}</option>
              </select>
            </FloatingField>

            <fieldset>
              <legend class="ls-label">{{ t('billing.billingCycle') }}</legend>
              <div class="grid grid-cols-2 gap-2" dir="ltr">
                <label class="ls-card-flat cursor-pointer p-3 text-center" :class="{ 'border-primary': interval === 'monthly' }">
                  <input v-model="interval" class="sr-only" type="radio" value="monthly">
                  <span class="block font-semibold">{{ t('billing.monthly') }}</span>
                  <span class="mt-1 block text-xs text-fg-muted">{{ t('billing.monthlyPrice') }}</span>
                </label>
                <label class="ls-card-flat cursor-pointer p-3 text-center" :class="{ 'border-primary': interval === 'yearly' }">
                  <input v-model="interval" class="sr-only" type="radio" value="yearly">
                  <span class="block font-semibold">{{ t('billing.yearly') }}</span>
                  <span class="mt-1 block text-xs text-fg-muted">{{ t('billing.yearlyPrice') }}</span>
                </label>
              </div>
            </fieldset>

            <div class="rounded-control border border-[var(--bs-border)] bg-surface-muted p-3 text-sm">
              <p class="font-semibold">{{ t('org.separateSubscriptionTitle') }}</p>
              <p class="mt-1 text-fg-muted">{{ t('org.separateSubscriptionBody') }}</p>
            </div>

            <p v-if="errorMessage" class="ls-error" role="alert">{{ errorMessage }}</p>
            <button type="submit" class="ls-btn ls-btn-accent w-full" :disabled="pending">
              {{ pending ? t('billing.openingCheckout') : pendingOrganizationId ? t('org.retryPayment') : t('org.createAndPay') }}
            </button>
          </form>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>
