import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { COLOR_SCHEMES } from 'dashboard/constants/colorSchemes';

export const setColorTheme = isOSOnDarkMode => {
  const selectedColorScheme =
    LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_SCHEME) || COLOR_SCHEMES.AUTO;
  const isDark =
    (selectedColorScheme === COLOR_SCHEMES.AUTO && isOSOnDarkMode) ||
    [COLOR_SCHEMES.DARK, COLOR_SCHEMES.BLACK].includes(selectedColorScheme);

  document.body.classList.toggle('dark', isDark);
  document.body.classList.toggle(
    'black',
    selectedColorScheme === COLOR_SCHEMES.BLACK
  );
  document.documentElement.style.setProperty(
    'color-scheme',
    isDark ? 'dark' : 'light'
  );
};
