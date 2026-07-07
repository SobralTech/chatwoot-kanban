<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';

import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SectionLayout from './components/SectionLayout.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const { t } = useI18n();
const { accountId } = useAccount();
const fileInputs = ref({});
const activeAsset = ref('');

const currentAccount = computed(
  () => store.getters['accounts/getAccount'](accountId.value) || {}
);

const branding = computed(() => currentAccount.value.branding || {});
const isUpdating = computed(
  () => store.getters['accounts/getUIFlags'].isUpdating
);
const assets = computed(() => [
  {
    key: 'logo',
    urlKey: 'logo_url',
    title: t('GENERAL_SETTINGS.BRANDING.ASSETS.LOGO.TITLE'),
    description: t('GENERAL_SETTINGS.BRANDING.ASSETS.LOGO.DESCRIPTION'),
    recommendation: t('GENERAL_SETTINGS.BRANDING.ASSETS.LOGO.RECOMMENDATION'),
  },
  {
    key: 'logo_dark',
    urlKey: 'logo_dark_url',
    title: t('GENERAL_SETTINGS.BRANDING.ASSETS.LOGO_DARK.TITLE'),
    description: t('GENERAL_SETTINGS.BRANDING.ASSETS.LOGO_DARK.DESCRIPTION'),
    recommendation: t(
      'GENERAL_SETTINGS.BRANDING.ASSETS.LOGO_DARK.RECOMMENDATION'
    ),
  },
  {
    key: 'favicon',
    urlKey: 'favicon_url',
    title: t('GENERAL_SETTINGS.BRANDING.ASSETS.FAVICON.TITLE'),
    description: t('GENERAL_SETTINGS.BRANDING.ASSETS.FAVICON.DESCRIPTION'),
    recommendation: t(
      'GENERAL_SETTINGS.BRANDING.ASSETS.FAVICON.RECOMMENDATION'
    ),
  },
]);

const openFilePicker = assetName => {
  fileInputs.value[assetName]?.click();
};

const onFileChange = async (assetName, event) => {
  const [file] = event.target.files || [];
  if (!file) return;

  activeAsset.value = assetName;
  try {
    await store.dispatch('accounts/updateBranding', { assetName, file });
    useAlert(t('GENERAL_SETTINGS.BRANDING.UPDATE.SUCCESS'));
  } catch {
    useAlert(t('GENERAL_SETTINGS.BRANDING.UPDATE.ERROR'));
  } finally {
    activeAsset.value = '';
    event.target.value = '';
  }
};

const removeAsset = async assetName => {
  activeAsset.value = assetName;
  try {
    await store.dispatch('accounts/deleteBranding', assetName);
    useAlert(t('GENERAL_SETTINGS.BRANDING.DELETE.SUCCESS'));
  } catch {
    useAlert(t('GENERAL_SETTINGS.BRANDING.DELETE.ERROR'));
  } finally {
    activeAsset.value = '';
  }
};
</script>

<template>
  <div class="flex flex-col w-full max-w-3xl ltr:mr-auto rtl:ml-auto">
    <BaseSettingsHeader :title="t('GENERAL_SETTINGS.BRANDING.TITLE')" />

    <SectionLayout
      :title="t('GENERAL_SETTINGS.BRANDING.SECTION.TITLE')"
      :description="t('GENERAL_SETTINGS.BRANDING.SECTION.NOTE')"
      class="!pt-3"
    >
      <div class="grid gap-4">
        <div
          v-for="asset in assets"
          :key="asset.key"
          class="grid gap-4 rounded-lg border border-n-weak bg-n-solid-1 p-4 sm:grid-cols-[8rem_1fr_auto] sm:items-center"
        >
          <div
            class="flex h-24 w-32 items-center justify-center rounded-lg border border-n-weak bg-n-slate-1"
          >
            <img
              v-if="branding[asset.urlKey]"
              :src="branding[asset.urlKey]"
              :alt="asset.title"
              class="max-h-16 max-w-24 object-contain"
            />
            <span v-else class="text-sm text-n-slate-10">
              {{ t('GENERAL_SETTINGS.BRANDING.EMPTY_PREVIEW') }}
            </span>
          </div>

          <div class="min-w-0">
            <h4 class="text-base font-medium text-n-slate-12">
              {{ asset.title }}
            </h4>
            <p class="mt-1 text-sm text-n-slate-11">
              {{ asset.description }}
            </p>
            <p class="mt-2 text-sm font-medium text-n-slate-12">
              {{ asset.recommendation }}
            </p>
          </div>

          <div class="flex flex-wrap items-center gap-2 sm:justify-end">
            <input
              :ref="element => (fileInputs[asset.key] = element)"
              type="file"
              accept="image/png,image/jpeg,image/webp,image/gif,image/x-icon"
              class="sr-only"
              @change="onFileChange(asset.key, $event)"
            />
            <NextButton
              slate
              :is-loading="isUpdating && activeAsset === asset.key"
              @click="openFilePicker(asset.key)"
            >
              {{ t('GENERAL_SETTINGS.BRANDING.UPLOAD') }}
            </NextButton>
            <NextButton
              v-if="branding[asset.urlKey]"
              ghost
              ruby
              :is-loading="isUpdating && activeAsset === asset.key"
              @click="removeAsset(asset.key)"
            >
              {{ t('GENERAL_SETTINGS.BRANDING.REMOVE') }}
            </NextButton>
          </div>
        </div>
      </div>
    </SectionLayout>
  </div>
</template>
