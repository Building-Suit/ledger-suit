<script setup lang="ts">
import { legalDocuments } from '~/utils/legal'

definePageMeta({ layout: 'marketing' })

const { locale } = useI18n()
const document = computed(() => legalDocuments.delivery[locale.value === 'ar' ? 'ar' : 'en'])
</script>

<template>
  <PublicLegalPage :document="document" />
</template>
