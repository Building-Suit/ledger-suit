<script setup lang="ts">
withDefaults(defineProps<{
  kind?: 'wordmark' | 'mark'
  tone?: 'auto' | 'light' | 'dark'
}>(), {
  kind: 'wordmark',
  tone: 'auto',
})
</script>

<template>
  <span
    class="ls-logo inline-grid shrink-0 place-items-center"
    :class="[`ls-logo-${kind}`, `ls-logo-${tone}`]"
    role="img"
    aria-label="Ledger Suit by Building Suit"
    dir="ltr"
  >
    <img
      class="ls-logo-image ls-logo-image-dark"
      :src="`/brand/ledger-suit-${kind}-dark.svg`"
      alt=""
      width="1040"
      height="300"
    >
    <img
      class="ls-logo-image ls-logo-image-light"
      :src="`/brand/ledger-suit-${kind}-light.svg`"
      alt=""
      width="1040"
      height="300"
    >
  </span>
</template>

<style scoped>
.ls-logo {
  line-height: 0;
}

.ls-logo-wordmark {
  aspect-ratio: 1040 / 300;
}

.ls-logo-mark {
  aspect-ratio: 1;
}

.ls-logo-image {
  grid-area: 1 / 1;
  width: 100%;
  height: 100%;
  object-fit: contain;
}

.ls-logo-image-light,
.ls-logo-light .ls-logo-image-dark {
  display: none;
}

.ls-logo-light .ls-logo-image-light {
  display: block;
}

:global(:root[data-theme='dark']) .ls-logo-auto .ls-logo-image-dark {
  display: none;
}

:global(:root[data-theme='dark']) .ls-logo-auto .ls-logo-image-light {
  display: block;
}

@media (prefers-color-scheme: dark) {
  :global(:root:not([data-theme='light']):not([data-theme='dark'])) .ls-logo-auto .ls-logo-image-dark {
    display: none;
  }

  :global(:root:not([data-theme='light']):not([data-theme='dark'])) .ls-logo-auto .ls-logo-image-light {
    display: block;
  }
}
</style>
