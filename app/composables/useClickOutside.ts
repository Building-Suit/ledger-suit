import type { Ref } from 'vue'

/**
 * Closes a popover when the user clicks away or presses Escape.
 *
 * Escape is handled here rather than per-component so every dropdown in the app
 * is dismissible from the keyboard without each one remembering to do it.
 */
export function useClickOutside(
  target: Ref<HTMLElement | null>,
  handler: () => void,
) {
  function onPointerDown(event: MouseEvent | TouchEvent) {
    const el = target.value
    if (!el) return
    if (event.target instanceof Node && !el.contains(event.target)) handler()
  }

  function onKeydown(event: KeyboardEvent) {
    if (event.key === 'Escape') handler()
  }

  onMounted(() => {
    document.addEventListener('pointerdown', onPointerDown)
    document.addEventListener('keydown', onKeydown)
  })

  onBeforeUnmount(() => {
    document.removeEventListener('pointerdown', onPointerDown)
    document.removeEventListener('keydown', onKeydown)
  })
}
