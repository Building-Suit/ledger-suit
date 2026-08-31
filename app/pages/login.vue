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
const mode = ref<'signin' | 'signup'>('signin')
const message = ref<string | null>(null)
const hydrated = ref(false)

onMounted(() => {
  restore()
  hydrated.value = true
})

watchEffect(() => {
  if (user.value) navigateTo('/')
})

async function signIn() {
  pending.value = true
  error.value = null

  const { data, error: signInError } = mode.value === 'signin'
    ? await supabase.auth.signInWithPassword({ email: email.value, password: password.value })
    : await supabase.auth.signUp({ email: email.value, password: password.value })

  pending.value = false
  // Deliberately generic: the form must not reveal whether an address exists.
  if (signInError) error.value = t('auth.failed')
  else if (mode.value === 'signup' && !data.session) message.value = t('auth.checkEmail')
  else await navigateTo('/')
}
</script>

<template>
  <main class="grid min-h-dvh place-items-center px-4">
    <div class="w-full max-w-sm">
      <form class="ls-card space-y-5 p-8" :data-hydrated="hydrated" @submit.prevent="signIn">
        <div>
          <h1 class="text-xl font-extrabold" dir="ltr">{{ t('auth.title') }}</h1>
          <p class="mt-1 text-sm text-fg-muted">{{ t(mode === 'signin' ? 'auth.subtitle' : 'auth.signupSubtitle') }}</p>
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
            :autocomplete="mode === 'signin' ? 'current-password' : 'new-password'"
            required
            dir="ltr"
            class="ls-input"
          >
        </div>

        <p v-if="error" role="alert" class="ls-error">{{ error }}</p>
        <p v-if="message" role="status" class="text-sm text-[var(--bs-status-success)]">{{ message }}</p>

        <button type="submit" :disabled="pending" class="ls-btn ls-btn-primary w-full">
          {{ pending ? t('auth.signingIn') : t(mode === 'signin' ? 'auth.signIn' : 'auth.signUp') }}
        </button>
        <button type="button" class="w-full text-sm text-link" @click="mode = mode === 'signin' ? 'signup' : 'signin'; error = null; message = null">{{ t(mode === 'signin' ? 'auth.needAccount' : 'auth.haveAccount') }}</button>
      </form>

      <div class="mt-4 flex justify-center">
        <SettingsMenu />
      </div>
    </div>
  </main>
</template>
