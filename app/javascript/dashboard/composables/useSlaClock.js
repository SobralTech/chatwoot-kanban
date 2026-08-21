import { onScopeDispose, ref } from 'vue';

const REFRESH_INTERVAL_MS = 60_000;

const now = ref(Date.now());
let subscribers = 0;
let timer = null;

// SLA badges have to move on their own - a card left on screen crosses its stage
// time limit without anything else changing. One shared timer drives every card,
// because a per-card interval would multiply by the size of the board, and it
// stops as soon as the last card unmounts.
export function useSlaClock() {
  subscribers += 1;
  if (!timer) {
    timer = setInterval(() => {
      now.value = Date.now();
    }, REFRESH_INTERVAL_MS);
  }

  onScopeDispose(() => {
    subscribers -= 1;
    if (subscribers > 0) return;

    clearInterval(timer);
    timer = null;
  });

  return now;
}
