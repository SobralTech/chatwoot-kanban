import { useAppearanceHotKeys } from '../useAppearanceHotKeys';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';

vi.mock('vue-i18n');
vi.mock('dashboard/composables/useUISettings');

describe('useAppearanceHotKeys', () => {
  const updateUISettings = vi.fn();

  beforeEach(() => {
    useI18n.mockReturnValue({
      t: vi.fn(key => key),
    });
    useUISettings.mockReturnValue({ updateUISettings });
  });

  it('should have the correct parent option', () => {
    const { goToAppearanceHotKeys } = useAppearanceHotKeys();
    const parentOption = goToAppearanceHotKeys.value.find(
      option => option.id === 'appearance_settings'
    );
    expect(parentOption.children.length).toBe(4);
  });

  it('should have the correct theme options', () => {
    const { goToAppearanceHotKeys } = useAppearanceHotKeys();
    const themeOptions = goToAppearanceHotKeys.value.filter(
      option => option.parent === 'appearance_settings'
    );
    expect(themeOptions.map(option => option.id)).toEqual([
      'light',
      'dark',
      'black',
      'auto',
    ]);
  });

  it.each(['light', 'dark', 'black', 'auto'])(
    'should save the %s theme to the user ui settings',
    colorScheme => {
      const { goToAppearanceHotKeys } = useAppearanceHotKeys();
      goToAppearanceHotKeys.value
        .find(option => option.id === colorScheme)
        .handler();

      expect(updateUISettings).toHaveBeenCalledWith({
        color_scheme: colorScheme,
      });
    }
  );
});
