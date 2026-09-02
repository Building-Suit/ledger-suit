<script setup lang="ts">
// No layout: the app shell assumes a signed-in user with an organization.
definePageMeta({ layout: false })

const { t } = useI18n()
useHead({ title: () => `${t('auth.signIn')} · ${t('app.name')}` })

const supabase = useSupabaseClient()
const user = useSupabaseUser()
const { restore } = useTheme()

const email = ref('')
const password = ref('')
const pending = ref(false)
const error = ref<string | null>(null)
const hydrated = ref(false)

onMounted(() => {
  restore()
  hydrated.value = true
})

watchEffect(() => {
  if (user.value) navigateTo('/dashboard')
})

async function signIn() {
  pending.value = true
  error.value = null

  const { error: signInError } = await supabase.auth.signInWithPassword({ email: email.value, password: password.value })

  pending.value = false
  // Deliberately generic: the form must not reveal whether an address exists.
  if (signInError) error.value = t('auth.failed')
  else await navigateTo('/dashboard')
}
</script>

<template>
  <main class="grid min-h-dvh bg-background lg:grid-cols-2">
    <section class="hidden bg-[var(--bs-ink)] p-12 text-[var(--bs-paper)] lg:flex lg:flex-col">
      <NuxtLink to="/" class="text-lg font-black tracking-[-.04em]" dir="ltr">
        Ledger Suit
        <span class="text-xs font-semibold" dir="ltr"> by Building Suit </span>
      </NuxtLink>
      <div class="my-auto max-w-xl"><p class="text-xs font-bold uppercase tracking-[.2em] text-[var(--bs-gray-400)]">{{ t('auth.welcomeEyebrow') }}</p><h1 class="mt-4 text-5xl font-black leading-tight tracking-[-.05em]">{{ t('auth.welcomeTitle') }}</h1><p class="mt-5 text-base leading-7 text-[var(--bs-gray-400)]">{{ t('auth.welcomeBody') }}</p></div>
      <p class="text-xs text-[var(--bs-gray-500)]" dir="ltr">© 2026 Building Suit</p>
    </section>
    <section class="grid place-items-center px-4 py-10">
      <div class="w-full max-w-md">
        <NuxtLink to="/" class="mb-8 inline-block text-lg font-black tracking-[-.04em] lg:hidden" dir="ltr">
          Ledger Suit
          <span class="text-xs font-semibold" dir="ltr"> by Building Suit </span>
        </NuxtLink>
      <form class="ls-card space-y-5 p-7 sm:p-9" :data-hydrated="hydrated" @submit.prevent="signIn">
        <div>
          <h1 class="text-xl font-extrabold" dir="ltr">{{ t('auth.title') }}</h1>
          <p class="mt-1 text-sm text-fg-muted">{{ t('auth.subtitle') }}</p>
        </div>

        <div>
          <label for="email" class="ls-label">{{ t('auth.email') }}</label>
          <input
            id="email"
            v-model="email"
            type="email"
            autocomplete="email"
            required
            dir="ltr"
            class="ls-input"
          >
        </div>

        <div>
          <label for="password" class="ls-label">{{ t('auth.password') }}</label>
          <input
            id="password"
            v-model="password"
            type="password"
            autocomplete="current-password"
            required
            dir="ltr"
            class="ls-input"
          >
        </div>

        <p v-if="error" role="alert" class="ls-error">{{ error }}</p>
        <button type="submit" :disabled="pending" class="ls-btn ls-btn-primary w-full">
          {{ pending ? t('auth.signingIn') : t('auth.signIn') }}
        </button>
        <p class="text-center text-sm text-fg-muted">{{ t('auth.needAccount') }} <NuxtLink to="/signup" class="font-bold text-fg underline underline-offset-4">{{ t('landing.startTrial') }}</NuxtLink></p>
      </form>

      <div class="mt-4 flex justify-center">
        <SettingsMenu />
      </div>
      </div>
    </section>
  </main>
</template>
