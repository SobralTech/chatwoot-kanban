import { mount } from '@vue/test-utils';
import AudioChip from '../Audio.vue';

const buildAttachment = (overrides = {}) => ({
  id: 1,
  fileType: 'audio',
  dataUrl:
    'https://storage.example.com/rails/active_storage/blobs/redirect/abc/audio.ogg',
  extension: 'ogg',
  transcribedText: '',
  ...overrides,
});

const mountAudioChip = (props = {}) =>
  mount(AudioChip, {
    props: { attachment: buildAttachment(), ...props },
  });

describe('Audio chip', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.spyOn(window.HTMLMediaElement.prototype, 'load').mockImplementation(
      () => {}
    );
    vi.spyOn(window.HTMLMediaElement.prototype, 'play').mockImplementation(
      () => {}
    );
    vi.spyOn(window.HTMLMediaElement.prototype, 'pause').mockImplementation(
      () => {}
    );
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('does not retry when the audio loads successfully', async () => {
    const wrapper = mountAudioChip();
    const load = window.HTMLMediaElement.prototype.load;

    await wrapper.find('audio').trigger('loadedmetadata');
    await vi.advanceTimersByTimeAsync(10000);

    expect(load).not.toHaveBeenCalled();
    expect(wrapper.text()).not.toContain('no longer available');
  });

  it('retries after the first failure and recovers on the second attempt', async () => {
    const wrapper = mountAudioChip();
    const load = window.HTMLMediaElement.prototype.load;

    await wrapper.find('audio').trigger('error');
    expect(load).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(1000);

    expect(load).toHaveBeenCalledTimes(1);
    expect(wrapper.text()).not.toContain('no longer available');
  });

  it('stops retrying and shows a definitive error after the max attempts', async () => {
    const wrapper = mountAudioChip();
    const load = window.HTMLMediaElement.prototype.load;

    await wrapper.find('audio').trigger('error'); // attempt 1 scheduled (1s)
    await vi.advanceTimersByTimeAsync(1000);
    await wrapper.find('audio').trigger('error'); // attempt 2 scheduled (2s)
    await vi.advanceTimersByTimeAsync(2000);
    await wrapper.find('audio').trigger('error'); // attempt 3 scheduled (4s)
    await vi.advanceTimersByTimeAsync(4000);
    await wrapper.find('audio').trigger('error'); // exceeds the limit

    expect(load).toHaveBeenCalledTimes(3);
    expect(wrapper.text()).toContain('This audio is no longer available.');
  });

  it('cancels pending retries when the component is unmounted', async () => {
    const wrapper = mountAudioChip();
    const load = window.HTMLMediaElement.prototype.load;

    await wrapper.find('audio').trigger('error');
    wrapper.unmount();

    await vi.advanceTimersByTimeAsync(10000);

    expect(load).not.toHaveBeenCalled();
  });

  it('resets the retry state when the attachment changes', async () => {
    const wrapper = mountAudioChip({ attachment: buildAttachment({ id: 1 }) });
    const load = window.HTMLMediaElement.prototype.load;

    await wrapper.find('audio').trigger('error'); // schedules a 1s retry for attachment 1

    await wrapper.setProps({
      attachment: buildAttachment({
        id: 2,
        dataUrl:
          'https://storage.example.com/rails/active_storage/blobs/redirect/def/audio.ogg',
      }),
    });

    await vi.advanceTimersByTimeAsync(1000);
    // The pending retry for attachment 1 must not leak into attachment 2.
    expect(load).not.toHaveBeenCalled();

    await wrapper.find('audio').trigger('error'); // fresh attempt 1 for attachment 2
    await vi.advanceTimersByTimeAsync(1000);
    expect(load).toHaveBeenCalledTimes(1);
    expect(wrapper.text()).not.toContain('no longer available');
  });
});
