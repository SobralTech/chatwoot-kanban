import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';

export const setColorTheme = isOSOnDarkMode => {
  const selectedColorScheme =
    LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_SCHEME) || 'auto';
  const isDark =
    (selectedColorScheme === 'auto' && isOSOnDarkMode) ||
    ['dark', 'black'].includes(selectedColorScheme);

  document.body.classList.toggle('dark', isDark);
  document.body.classList.toggle('black', selectedColorScheme === 'black');
  document.documentElement.style.setProperty(
    'color-scheme',
    isDark ? 'dark' : 'light'
  );
};
