import { isApple } from './platform';

export const isEnter = e => {
  return e.key === 'Enter';
};

export const isEscape = e => {
  return e.key === 'Escape';
};

export const hasPressedShift = e => {
  return e.shiftKey;
};

export const hasPressedCommand = e => {
  return e.metaKey;
};

// True when the platform's "command" modifier is held: Cmd (metaKey) on
// Apple platforms (macOS, iOS/iPadOS hardware keyboards), Ctrl (ctrlKey)
// elsewhere. Mirrors the `$mod` convention used by tinykeys and
// prosemirror-keymap so the editor and the app agree on what counts as the
// send modifier.
export const hasPressedMod = e => Boolean(isApple() ? e.metaKey : e.ctrlKey);

export const hasPressedEnterAndNotCmdOrShift = e => {
  return isEnter(e) && !hasPressedMod(e) && !hasPressedShift(e);
};

// True while an IME / OS text-suggestion composition is in progress. `keyCode === 229`
// is the legacy signal some browsers send for the composing keydown. Null-safe because
// some keyboard handlers invoke `action` without an event argument.
export const isInComposition = event =>
  Boolean(event?.isComposing || event?.keyCode === 229);

// Detects the platform-aware "send" shortcut: Cmd+Enter on Apple platforms,
// Ctrl+Enter on Windows/Linux.
export const hasPressedCommandAndEnter = e => hasPressedMod(e) && isEnter(e);

// If layout is QWERTZ then we add the Shift+keysToModify to fix an known issue
// https://github.com/chatwoot/chatwoot/issues/9492
export const keysToModifyInQWERTZ = new Set(['Alt+KeyP', 'Alt+KeyL']);

export const LAYOUT_QWERTY = 'QWERTY';
export const LAYOUT_QWERTZ = 'QWERTZ';
export const LAYOUT_AZERTY = 'AZERTY';

/**
 * Determines whether the active element is typeable.
 *
 * @param {KeyboardEvent} e - The keyboard event object.
 * @returns {boolean} `true` if the active element is typeable, `false` otherwise.
 *
 * @example
 * document.addEventListener('keydown', e => {
 *   if (isActiveElementTypeable(e)) {
 *     handleTypeableElement(e);
 *   }
 * });
 */
export const isActiveElementTypeable = e => {
  /** @type {HTMLElement | null} */
  // @ts-ignore
  const activeElement = e.target || document.activeElement;

  return !!(
    activeElement?.tagName === 'INPUT' ||
    activeElement?.tagName === 'NINJA-KEYS' ||
    activeElement?.tagName === 'TEXTAREA' ||
    activeElement?.contentEditable === 'true' ||
    activeElement?.className?.includes('ProseMirror')
  );
};
