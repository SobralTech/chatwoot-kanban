import { ref, onBeforeUnmount } from 'vue';

const DEFAULT_MAX_RETRIES = 3;
const DEFAULT_BASE_DELAY = 1000; // ms, doubles each attempt: 1s, 2s, 4s

// Retries a native <audio>/<video> element load after a transient failure
// (e.g. the storage object not being replicated yet when a realtime
// attachment arrives). Unlike useLoadWithRetry (Image-based), this drives
// the actual media element so Range/206 streaming keeps working.
export const useMediaRetry = (config = {}) => {
  const maxRetries = config.maxRetries ?? DEFAULT_MAX_RETRIES;
  const baseDelay = config.baseDelay ?? DEFAULT_BASE_DELAY;

  const hasError = ref(false);
  const cacheBustParam = ref(Date.now());
  let attempts = 0;
  let timer = null;

  const clearTimer = () => {
    if (timer) {
      clearTimeout(timer);
      timer = null;
    }
  };

  const reset = () => {
    clearTimer();
    attempts = 0;
    hasError.value = false;
    cacheBustParam.value += 1;
  };

  const scheduleRetry = reload => {
    if (attempts >= maxRetries) {
      clearTimer();
      hasError.value = true;
      return;
    }

    const delay = baseDelay * 2 ** attempts;
    attempts += 1;
    clearTimer();
    timer = setTimeout(() => {
      timer = null;
      cacheBustParam.value += 1;
      reload();
    }, delay);
  };

  onBeforeUnmount(clearTimer);

  return { hasError, cacheBustParam, scheduleRetry, reset };
};
