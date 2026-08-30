<script setup lang="ts">
const supabase = useSupabaseClient()
const user = useSupabaseUser()

const email = ref('')
const password = ref('')
const pending = ref(false)
const error = ref<string | null>(null)

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
  if (signInError) error.value = 'Those credentials did not work. Please try again.'
}
</script>

<template>
  <main class="grid min-h-dvh place-items-center px-4">
    <form
      class="w-full max-w-sm space-y-5 rounded-xl border border-neutral-200 bg-white p-8 dark:border-neutral-800 dark:bg-neutral-900"
      @submit.prevent="signIn"
    >
      <div>
        <h1 class="text-xl font-semibold">Ledger Suit</h1>
        <p class="mt-1 text-sm text-neutral-500">Sign in to your organization.</p>
      </div>

      <div class="space-y-1">
        <label for="email" class="block text-sm font-medium">Email</label>
        <input
          id="email"
          v-model="email"
          type="email"
          autocomplete="email"
          required
          class="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm focus:border-neutral-900 focus:outline-2 focus:outline-offset-2 focus:outline-neutral-900 dark:border-neutral-700 dark:bg-neutral-950"
        >
      </div>

      <div class="space-y-1">
        <label for="password" class="block text-sm font-medium">Password</label>
        <input
          id="password"
          v-model="password"
          type="password"
          autocomplete="current-password"
          required
          class="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm focus:border-neutral-900 focus:outline-2 focus:outline-offset-2 focus:outline-neutral-900 dark:border-neutral-700 dark:bg-neutral-950"
        >
      </div>

      <p v-if="error" role="alert" class="text-sm text-red-600">{{ error }}</p>

      <button
        type="submit"
        :disabled="pending"
        class="w-full rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white disabled:opacity-50 dark:bg-white dark:text-neutral-900"
      >
        {{ pending ? 'Signing in…' : 'Sign in' }}
      </button>
    </form>
  </main>
</template>
