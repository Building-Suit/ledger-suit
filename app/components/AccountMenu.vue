<script setup lang="ts">
import type { Database } from '~~/types/database.types'

const supabase = useSupabaseClient<Database>()
const user = useSupabaseUser()
const route = useRoute()
const { t } = useI18n()
const { can } = useTenant()

const open = ref(false)
const root = ref<HTMLElement | null>(null)
const hasWorkspaceActions = computed(() => can('billing.read'))
const userId = computed(() => user.value?.id)

const { data: profile } = useLazyAsyncData('account:profile', async () => {
  if (!userId.value) return null

  const { data, error } = await supabase
    .from('profiles')
    .select('full_name')
    .eq('id', userId.value)
    .maybeSingle()

  if (error) throw error
  return data
}, { watch: [userId] })

const fullName = computed(() => {
  if (profile.value?.full_name) return profile.value.full_name

  const metadataName = user.value?.user_metadata.full_name
    ?? user.value?.user_metadata.name

  return typeof metadataName === 'string' ? metadataName : ''
})

useClickOutside(root, () => (open.value = false))

watch(() => route.fullPath, () => (open.value = false))

async function signOut() {
  open.value = false
  await supabase.auth.signOut()
  await navigateTo('/login')
}
</script>

<template>
  <div ref="root" class="relative">
    <button
      type="button"
      class="ls-btn ls-btn-sm"
      :aria-label="t('common.accountMenu')"
      :aria-expanded="open"
      aria-haspopup="menu"
      @click="open = !open"
    >
      <AppIcon name="user" />
    </button>

    <div
      v-show="open"
      class="ls-card absolute end-0 z-40 mt-1 max-h-[calc(100dvh-5rem)] w-[min(18rem,calc(100vw-2rem))] space-y-2 overflow-y-auto p-2 shadow-overlay"
      role="menu"
    >
      <div v-if="fullName || user?.email" class="px-2 py-1" dir="auto">
        <p v-if="fullName" class="truncate font-semibold text-fg">
          {{ fullName }}
        </p>
        <p v-if="user?.email" class="truncate text-sm text-fg-muted">
          {{ user.email }}
        </p>
      </div>

      <hr v-if="fullName || user?.email" class="border-[var(--bs-border)]">

      <NuxtLink
        v-if="can('billing.read')"
        to="/billing"
        class="ls-btn ls-btn-sm w-full"
        role="menuitem"
      >
        {{ t('billing.title') }}
      </NuxtLink>

      <hr v-if="hasWorkspaceActions" class="border-[var(--bs-border)]">

      <SettingsMenu embedded />

      <hr class="border-[var(--bs-border)]">

      <button type="button" class="ls-btn ls-btn-danger ls-btn-sm w-full" role="menuitem" @click="signOut">
        {{ t('common.signOut') }}
      </button>
    </div>

    <TeamMenu :show-trigger="false" />
  </div>
</template>
