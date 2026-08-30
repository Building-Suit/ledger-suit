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

onMounted(restore)

watchEffect(() => {
  if (user.value) navigateTo('/')
})

async function signIn() {
  pending.value = true
  error.value = null

  const { error: signInError } = await supabase.auth.signInWithPassword({
    email: email.value,
    password: password.value,
  })

  pending.value = false
  // Deliberately generic: the form must not reveal whether an address exists.
  if (signInError) error.value = t('auth.failed')
}
</script>

<template>
  <main class="grid min-h-dvh place-items-center px-4">
    <div class="w-full max-w-sm">
      <form class="ls-card space-y-5 p-8" @submit.prevent="signIn">
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
      </form>

      <div class="mt-4 flex justify-center">
        <SettingsMenu />
      </div>
    </div>
  </main>
</template>
