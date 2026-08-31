<script setup lang="ts">
import type { Database } from '~~/types/database.types'

const supabase = useSupabaseClient<Database>()
const { currentId } = useTenant()
const { t } = useI18n()
const open = ref(false)
const root = ref<HTMLElement | null>(null)
useClickOutside(root, () => (open.value = false))

const { data: notifications, refresh } = await useAsyncData('org:notifications', async () => {
  if (!currentId.value) return []
  const { data, error } = await supabase.from('notifications').select('*').eq('organization_id', currentId.value).order('created_at', { ascending: false }).limit(20)
  if (error) throw error
  return data ?? []
}, { watch: [currentId], default: () => [] })

const unread = computed(() => notifications.value.filter(n => !n.read_at).length)
async function markRead(id: string) { await supabase.rpc('mark_notification_read' as never, { p_notification_id: id } as never); await refresh() }
async function markAll() { if (!currentId.value) return; await supabase.rpc('mark_all_notifications_read' as never, { p_organization_id: currentId.value } as never); await refresh() }
</script>

<template>
  <div ref="root" class="relative">
    <button type="button" class="ls-btn ls-btn-sm relative" :aria-label="t('notifications.title')" :aria-expanded="open" @click="open = !open">
      <span aria-hidden="true">♢</span><span v-if="unread" class="ls-badge bg-[var(--bs-status-error)] text-white">{{ unread }}</span>
    </button>
    <div v-if="open" class="ls-card absolute end-0 z-40 mt-1 w-[min(24rem,calc(100vw-2rem))] p-2 shadow-overlay">
      <div class="flex items-center justify-between px-2 py-2"><h2 class="font-bold">{{ t('notifications.title') }}</h2><button v-if="unread" class="text-xs text-link" @click="markAll">{{ t('notifications.markAll') }}</button></div>
      <p v-if="!notifications.length" class="px-2 py-6 text-center text-sm text-fg-muted">{{ t('notifications.empty') }}</p>
      <button v-for="item in notifications" :key="item.id" class="block w-full rounded-chip px-3 py-2 text-start hover:bg-surface-muted" :class="{ 'bg-surface-muted': !item.read_at }" @click="markRead(item.id)"><span class="block text-sm font-semibold">{{ item.title }}</span><span class="block text-xs text-fg-muted">{{ item.body }}</span></button>
    </div>
  </div>
</template>
