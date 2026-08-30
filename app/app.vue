<template>
  <div class="min-h-dvh">
    <NuxtRouteAnnouncer />
    <!-- NuxtLayout is required for definePageMeta({ layout }) to take effect.
         Without it every page renders bare and the tenant context in the
         default layout never loads. -->
    <NuxtLayout>
      <NuxtPage />
    </NuxtLayout>
  </div>
</template>
