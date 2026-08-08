import { mount } from '@vue/test-utils';
import { defineComponent, h } from 'vue';
import { createStore } from 'vuex';
import { provideMessageContext } from '../../provider.js';
import VideoChip from '../Video.vue';

const createStoreConfig = () =>
  createStore({
    getters: {
      getSelectedChatAttachments: () => [],
    },
  });

const buildAttachment = (overrides = {}) => ({
  id: 1,
  fileType: 'video',
  dataUrl:
    'https://storage.example.com/rails/active_storage/blobs/redirect/abc/video.mp4',
  extension: 'mp4',
  ...overrides,
});

// chips/Video.vue reads useMessageContext() for the gallery's attachment
// list, which requires a <Message> ancestor providing that context.
const Harness = defineComponent({
  props: { attachment: { type: Object, required: true } },
  setup(props) {
    provideMessageContext({});
    return () => h(VideoChip, { attachment: props.attachment });
  },
});

const mountVideoChip = (props = {}) =>
  mount(Harness, {
    props: { attachment: buildAttachment(), ...props },
    global: { plugins: [createStoreConfig()] },
  });

describe('Video chip', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.spyOn(window.HTMLMediaElement.prototype, 'load').mockImplementation(
      () => {}
    );
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('does not retry when the video loads successfully', async () => {
    const wrapper = mountVideoChip();

    await vi.advanceTimersByTimeAsync(10000);

    expect(window.HTMLMediaElement.prototype.load).not.toHaveBeenCalled();
    expect(wrapper.text()).not.toContain('Loading failed');
  });

  it('retries after a transient failure and recovers', async () => {
    const wrapper = mountVideoChip();
    const load = window.HTMLMediaElement.prototype.load;

    await wrapper.find('video').trigger('error');
    await vi.advanceTimersByTimeAsync(1000);

    expect(load).toHaveBeenCalledTimes(1);
    expect(wrapper.text()).not.toContain('Loading failed');
  });

  it('shows a definitive error after exceeding the retry limit', async () => {
    const wrapper = mountVideoChip();

    await wrapper.find('video').trigger('error');
    await vi.advanceTimersByTimeAsync(1000);
    await wrapper.find('video').trigger('error');
    await vi.advanceTimersByTimeAsync(2000);
    await wrapper.find('video').trigger('error');
    await vi.advanceTimersByTimeAsync(4000);
    await wrapper.find('video').trigger('error');

    expect(wrapper.text()).toContain('Loading failed');
  });
});
