import { shallowMount } from '@vue/test-utils';
import { defineComponent } from 'vue';
import { useMediaRetry } from '../useMediaRetry';

const mountComposable = (config = {}) => {
  let composable;
  const TestComponent = defineComponent({
    setup() {
      composable = useMediaRetry(config);
      return composable;
    },
    template: '<div></div>',
  });
  const wrapper = shallowMount(TestComponent);
  return {
    wrapper,
    get composable() {
      return composable;
    },
  };
};

describe('useMediaRetry', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('does not retry or error when the media is never reported as failed', () => {
    const { composable } = mountComposable();
    expect(composable.hasError.value).toBe(false);

    vi.advanceTimersByTime(10000);

    expect(composable.hasError.value).toBe(false);
  });

  it('retries after a transient failure and recovers', () => {
    const { composable } = mountComposable();
    const reload = vi.fn();

    composable.scheduleRetry(reload);
    expect(reload).not.toHaveBeenCalled();
    expect(composable.hasError.value).toBe(false);

    vi.advanceTimersByTime(1000);

    expect(reload).toHaveBeenCalledTimes(1);
    expect(composable.hasError.value).toBe(false);
  });

  it('uses an exponential backoff between attempts', () => {
    const { composable } = mountComposable();
    const reload = vi.fn();

    composable.scheduleRetry(reload);
    vi.advanceTimersByTime(999);
    expect(reload).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(reload).toHaveBeenCalledTimes(1);

    composable.scheduleRetry(reload);
    vi.advanceTimersByTime(1999);
    expect(reload).toHaveBeenCalledTimes(1);
    vi.advanceTimersByTime(1);
    expect(reload).toHaveBeenCalledTimes(2);
  });

  it('gives up and sets a definitive error after exceeding the retry limit', () => {
    const { composable } = mountComposable({ maxRetries: 3, baseDelay: 1000 });
    const reload = vi.fn();

    composable.scheduleRetry(reload); // attempt 1 scheduled
    vi.advanceTimersByTime(1000);
    composable.scheduleRetry(reload); // attempt 2 scheduled
    vi.advanceTimersByTime(2000);
    composable.scheduleRetry(reload); // attempt 3 scheduled
    vi.advanceTimersByTime(4000);

    expect(reload).toHaveBeenCalledTimes(3);
    expect(composable.hasError.value).toBe(false);

    // 4th failure exceeds maxRetries: no further timer, definitive error
    composable.scheduleRetry(reload);
    expect(composable.hasError.value).toBe(true);
    expect(vi.getTimerCount()).toBe(0);

    vi.advanceTimersByTime(10000);
    expect(reload).toHaveBeenCalledTimes(3);
  });

  it('cancels a pending retry when the component is unmounted', () => {
    const { wrapper, composable } = mountComposable();
    const reload = vi.fn();

    composable.scheduleRetry(reload);
    wrapper.unmount();

    vi.advanceTimersByTime(10000);

    expect(reload).not.toHaveBeenCalled();
  });

  it('resets retry state and cache-bust token when the attachment changes', () => {
    const { composable } = mountComposable({ maxRetries: 3, baseDelay: 1000 });
    const reload = vi.fn();

    composable.scheduleRetry(reload); // attempt 1
    vi.advanceTimersByTime(1000);
    composable.scheduleRetry(reload); // attempt 2
    vi.advanceTimersByTime(2000);
    composable.scheduleRetry(reload); // attempt 3
    vi.advanceTimersByTime(4000);
    composable.scheduleRetry(reload); // exceeds the limit
    expect(composable.hasError.value).toBe(true);

    const bustBeforeReset = composable.cacheBustParam.value;
    composable.reset();

    expect(composable.hasError.value).toBe(false);
    expect(composable.cacheBustParam.value).not.toBe(bustBeforeReset);

    // A fresh failure after reset should be able to retry again from attempt 1
    const reloadAfterReset = vi.fn();
    composable.scheduleRetry(reloadAfterReset);
    vi.advanceTimersByTime(1000);
    expect(reloadAfterReset).toHaveBeenCalledTimes(1);
  });
});
