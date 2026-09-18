import {
  applyUserColorScheme,
  useColorScheme,
} from 'dashboard/composables/useColorScheme';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { setColorTheme } from 'dashboard/helper/themeHelper';
import { nextTick, ref } from 'vue';

vi.mock('shared/helpers/localStorage');
vi.mock('dashboard/helper/themeHelper');

describe('applyUserColorScheme', () => {
  beforeEach(() => {
    window.matchMedia = vi.fn().mockReturnValue({ matches: false });
  });

  it('applies the color scheme saved in the user profile', () => {
    applyUserColorScheme('black');

    expect(LocalStorage.set).toHaveBeenCalledWith(
      LOCAL_STORAGE_KEYS.COLOR_SCHEME,
      'black'
    );
    expect(setColorTheme).toHaveBeenCalledWith(false);
  });

  it('resets to auto when the next user has no saved color scheme', () => {
    applyUserColorScheme();

    expect(LocalStorage.set).toHaveBeenCalledWith(
      LOCAL_STORAGE_KEYS.COLOR_SCHEME,
      'auto'
    );
    expect(setColorTheme).toHaveBeenCalledWith(false);
  });

  it('resets the browser scheme when switching to a user without a preference', async () => {
    const uiSettings = ref({ color_scheme: 'black' });
    useColorScheme(uiSettings);

    uiSettings.value = {};
    await nextTick();

    expect(LocalStorage.set).toHaveBeenLastCalledWith(
      LOCAL_STORAGE_KEYS.COLOR_SCHEME,
      'auto'
    );
  });
});
