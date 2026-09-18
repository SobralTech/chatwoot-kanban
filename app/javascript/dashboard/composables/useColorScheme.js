import { watch } from 'vue';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { COLOR_SCHEMES } from 'dashboard/constants/colorSchemes';
import { setColorTheme } from 'dashboard/helper/themeHelper';

export const applyUserColorScheme = colorScheme => {
  const selectedColorScheme = colorScheme || COLOR_SCHEMES.AUTO;
  LocalStorage.set(LOCAL_STORAGE_KEYS.COLOR_SCHEME, selectedColorScheme);
  setColorTheme(window.matchMedia('(prefers-color-scheme: dark)').matches);
};

export const useColorScheme = uiSettings => {
  watch(
    () => uiSettings.value?.color_scheme,
    colorScheme => applyUserColorScheme(colorScheme),
    { immediate: true }
  );
};
