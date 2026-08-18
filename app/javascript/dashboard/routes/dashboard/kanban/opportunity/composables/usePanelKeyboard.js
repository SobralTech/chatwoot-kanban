import { onMounted, onUnmounted, nextTick, ref } from 'vue';

const FOCUSABLE_SELECTOR =
  'a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])';

/**
 * Keyboard and focus ownership of a modal panel: focus starts on the container,
 * Tab cycles inside it and returns to the opener on close.
 *
 * `isBlocked` reports whether another dialog is stacked above the panel. While
 * it is, the panel handles nothing: pulling focus back would make the dialog
 * unreachable by keyboard, and Escape would immediately reopen it.
 */
export function usePanelKeyboard({ panelRef, isBlocked, onSave, onClose }) {
  const previousActiveElement = ref(null);

  const cycleFocus = event => {
    const focusableElements = [
      ...panelRef.value.querySelectorAll(FOCUSABLE_SELECTOR),
    ];
    if (!focusableElements.length) return;

    const firstElement = focusableElements[0];
    const lastElement = focusableElements.at(-1);

    if (document.activeElement === panelRef.value) {
      event.preventDefault();
      (event.shiftKey ? lastElement : firstElement).focus();
    } else if (event.shiftKey && document.activeElement === firstElement) {
      event.preventDefault();
      lastElement.focus();
    } else if (!event.shiftKey && document.activeElement === lastElement) {
      event.preventDefault();
      firstElement.focus();
    }
  };

  const onKeydown = event => {
    if (!panelRef.value || isBlocked()) return;

    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 's') {
      event.preventDefault();
      onSave();
      return;
    }
    if (event.key === 'Escape') {
      event.preventDefault();
      onClose();
      return;
    }
    if (event.key === 'Tab') cycleFocus(event);
  };

  onMounted(() => {
    previousActiveElement.value = document.activeElement;
    document.addEventListener('keydown', onKeydown);
    nextTick(() => panelRef.value?.focus());
  });

  onUnmounted(() => {
    document.removeEventListener('keydown', onKeydown);
    if (previousActiveElement.value?.isConnected) {
      previousActiveElement.value.focus();
    }
  });
}
