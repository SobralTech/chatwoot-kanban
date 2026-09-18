import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  ICON_APPEARANCE,
  ICON_LIGHT_MODE,
  ICON_DARK_MODE,
  ICON_SYSTEM_MODE,
} from 'dashboard/helper/commandbar/icons';
import { useUISettings } from 'dashboard/composables/useUISettings';

const getThemeOptions = t => [
  {
    key: 'light',
    label: t('COMMAND_BAR.COMMANDS.LIGHT_MODE'),
    icon: ICON_LIGHT_MODE,
  },
  {
    key: 'dark',
    label: t('COMMAND_BAR.COMMANDS.DARK_MODE'),
    icon: ICON_DARK_MODE,
  },
  {
    key: 'black',
    label: t('COMMAND_BAR.COMMANDS.BLACK_MODE'),
    icon: ICON_DARK_MODE,
  },
  {
    key: 'auto',
    label: t('COMMAND_BAR.COMMANDS.SYSTEM_MODE'),
    icon: ICON_SYSTEM_MODE,
  },
];

export function useAppearanceHotKeys() {
  const { t } = useI18n();
  const { updateUISettings } = useUISettings();

  const themeOptions = computed(() => getThemeOptions(t));

  const goToAppearanceHotKeys = computed(() => {
    const options = themeOptions.value.map(theme => ({
      id: theme.key,
      title: theme.label,
      parent: 'appearance_settings',
      section: t('COMMAND_BAR.SECTIONS.APPEARANCE'),
      icon: theme.icon,
      handler: () => {
        updateUISettings({ color_scheme: theme.key });
      },
    }));
    return [
      {
        id: 'appearance_settings',
        title: t('COMMAND_BAR.COMMANDS.CHANGE_APPEARANCE'),
        section: t('COMMAND_BAR.SECTIONS.APPEARANCE'),
        icon: ICON_APPEARANCE,
        children: options.map(option => option.id),
      },
      ...options,
    ];
  });

  return {
    goToAppearanceHotKeys,
  };
}
