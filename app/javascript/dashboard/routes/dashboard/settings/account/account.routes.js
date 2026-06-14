import { frontendURL } from '../../../../helper/URLHelper';
import Index from './Index.vue';
import Branding from './Branding.vue';
import SettingsWrapper from '../SettingsWrapper.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/general'),
      meta: {
        permissions: ['administrator'],
      },
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'general_settings_index',
          component: Index,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
    {
      path: frontendURL('accounts/:accountId/settings/branding'),
      meta: {
        permissions: ['administrator'],
      },
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'branding_settings_index',
          component: Branding,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
