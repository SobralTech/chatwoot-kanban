<script setup>
/* global axios */
import { ref, computed, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useVuelidate } from '@vuelidate/core';
import { required, url } from '@vuelidate/validators';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { accountId } = useAccount();

const name = ref('');
const wahaUrl = ref('');
const apiKey = ref('');
const sessionName = ref('');
const phoneNumber = ref('');
const groupsEnabled = ref(false);
const autoReconnect = ref(true);
const autoReadReceipts = ref(true);

const createdInboxId = ref(null);
const webhookUrl = ref('');
const sessionStatus = ref('');
const qrCode = ref('');
let pollInterval = null;
const isCancelling = ref(false);

const uiFlags = computed(() => store.getters['inboxes/getUIFlags']);
const isConnected = computed(() => sessionStatus.value === 'WORKING');

const displayStatus = computed(() => {
  if (!sessionStatus.value)
    return t('INBOX_MGMT.ADD.WAHA_CHANNEL.SESSION.STARTING');
  const key = `INBOX_MGMT.ADD.WAHA_CHANNEL.SESSION.STATUSES.${sessionStatus.value}`;
  const translated = t(key);
  // Fall back to the raw WAHA status for values we don't have a label for
  return translated === key ? sessionStatus.value : translated;
});

const rules = {
  name: { required },
  wahaUrl: { required, url },
  apiKey: { required },
  sessionName: { required },
};

const v$ = useVuelidate(rules, { name, wahaUrl, apiKey, sessionName });

async function pollSessionStatus() {
  if (!createdInboxId.value || isConnected.value) return;
  try {
    const resp = await axios.get(
      `/api/v1/accounts/${accountId.value}/inboxes/${createdInboxId.value}/waha_session_status`
    );
    sessionStatus.value = resp.data.status || '';
    qrCode.value = resp.data.qr_code || '';

    if (isConnected.value) {
      clearInterval(pollInterval);
      pollInterval = null;
    }
  } catch {
    // silently ignore poll errors
  }
}

async function createChannel() {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  try {
    const inbox = await store.dispatch('inboxes/createChannel', {
      name: name.value,
      channel: {
        type: 'waha',
        phone_number: phoneNumber.value,
        waha_url: wahaUrl.value,
        api_key: apiKey.value,
        session_name: sessionName.value,
        groups_enabled: groupsEnabled.value,
        auto_reconnect: autoReconnect.value,
        auto_read_receipts: autoReadReceipts.value,
      },
    });

    createdInboxId.value = inbox.id;
    webhookUrl.value = inbox.channel_config?.webhook_url || '';

    // Start polling for QR / session status
    await pollSessionStatus();
    pollInterval = setInterval(pollSessionStatus, 3000);
  } catch (error) {
    useAlert(
      error.message || t('INBOX_MGMT.ADD.WAHA_CHANNEL.API.ERROR_MESSAGE')
    );
  }
}

async function copyWebhookUrl() {
  await navigator.clipboard.writeText(webhookUrl.value);
  useAlert(t('INBOX_MGMT.ADD.WAHA_CHANNEL.WEBHOOK_COPIED'));
}

function proceed() {
  clearInterval(pollInterval);
  router.replace({
    name: 'settings_inboxes_add_agents',
    params: { page: 'new', inbox_id: createdInboxId.value },
  });
}

async function cancel() {
  clearInterval(pollInterval);
  pollInterval = null;

  if (createdInboxId.value) {
    isCancelling.value = true;
    try {
      await store.dispatch('inboxes/delete', createdInboxId.value);
    } catch {
      // ignore — inbox may not exist yet, we still navigate away
    } finally {
      isCancelling.value = false;
    }
  }

  router.replace({ name: 'settings_inbox_list' });
}

onUnmounted(() => {
  if (pollInterval) clearInterval(pollInterval);
});
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <PageHeader
      :header-title="$t('INBOX_MGMT.ADD.WAHA_CHANNEL.TITLE')"
      :header-content="$t('INBOX_MGMT.ADD.WAHA_CHANNEL.DESC')"
    />

    <!-- Setup form — hidden after inbox is created -->
    <form
      v-if="!createdInboxId"
      class="flex flex-col gap-4 mx-0"
      @submit.prevent="createChannel"
    >
      <label :class="{ error: v$.name.$error }">
        {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.NAME.LABEL') }}
        <input
          v-model="name"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WAHA_CHANNEL.NAME.PLACEHOLDER')"
          @blur="v$.name.$touch"
        />
        <span v-if="v$.name.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.NAME.ERROR') }}
        </span>
      </label>

      <label :class="{ error: v$.wahaUrl.$error }">
        {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.WAHA_URL.LABEL') }}
        <input
          v-model="wahaUrl"
          type="url"
          :placeholder="$t('INBOX_MGMT.ADD.WAHA_CHANNEL.WAHA_URL.PLACEHOLDER')"
          @blur="v$.wahaUrl.$touch"
        />
        <span v-if="v$.wahaUrl.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.WAHA_URL.ERROR') }}
        </span>
      </label>

      <label :class="{ error: v$.apiKey.$error }">
        {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.API_KEY.LABEL') }}
        <input
          v-model="apiKey"
          type="password"
          :placeholder="$t('INBOX_MGMT.ADD.WAHA_CHANNEL.API_KEY.PLACEHOLDER')"
          @blur="v$.apiKey.$touch"
        />
        <span v-if="v$.apiKey.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.API_KEY.ERROR') }}
        </span>
      </label>

      <label :class="{ error: v$.sessionName.$error }">
        {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.SESSION_NAME.LABEL') }}
        <input
          v-model="sessionName"
          type="text"
          :placeholder="
            $t('INBOX_MGMT.ADD.WAHA_CHANNEL.SESSION_NAME.PLACEHOLDER')
          "
          @blur="v$.sessionName.$touch"
        />
        <span v-if="v$.sessionName.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.SESSION_NAME.ERROR') }}
        </span>
      </label>

      <label>
        {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.PHONE_NUMBER.LABEL') }}
        <input
          v-model="phoneNumber"
          type="tel"
          :placeholder="
            $t('INBOX_MGMT.ADD.WAHA_CHANNEL.PHONE_NUMBER.PLACEHOLDER')
          "
        />
      </label>

      <div class="flex flex-col gap-2">
        <label class="flex items-center gap-2 cursor-pointer">
          <input v-model="groupsEnabled" type="checkbox" class="checkbox" />
          {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.GROUPS_ENABLED.LABEL') }}
        </label>
        <label class="flex items-center gap-2 cursor-pointer">
          <input v-model="autoReconnect" type="checkbox" class="checkbox" />
          {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.AUTO_RECONNECT.LABEL') }}
        </label>
        <label class="flex items-center gap-2 cursor-pointer">
          <input v-model="autoReadReceipts" type="checkbox" class="checkbox" />
          {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.AUTO_READ_RECEIPTS.LABEL') }}
        </label>
      </div>

      <div class="mt-2 flex gap-2">
        <NextButton
          :is-loading="uiFlags.isCreating"
          type="submit"
          solid
          blue
          :label="$t('INBOX_MGMT.ADD.WAHA_CHANNEL.SUBMIT_BUTTON')"
        />
        <NextButton
          type="button"
          :label="$t('INBOX_MGMT.ADD.WAHA_CHANNEL.CANCEL_BUTTON')"
          @click="cancel"
        />
      </div>
    </form>

    <!-- Post-creation: QR code + webhook URL -->
    <div v-if="createdInboxId" class="flex flex-col gap-6 mt-4">
      <!-- Session status -->
      <div
        class="p-4 rounded-lg border"
        :class="
          isConnected
            ? 'border-n-teal-6 bg-n-teal-3'
            : 'border-n-amber-6 bg-n-amber-3'
        "
      >
        <p class="font-semibold text-sm text-n-slate-12">
          {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.SESSION.STATUS_LABEL') }}:
          <span :class="isConnected ? 'text-n-teal-11' : 'text-n-amber-11'">
            {{ displayStatus }}
          </span>
        </p>
      </div>

      <!-- QR Code -->
      <div v-if="qrCode" class="flex flex-col items-center gap-2">
        <p class="text-sm font-semibold">
          {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.SESSION.QR_LABEL') }}
        </p>
        <img :src="qrCode" alt="WhatsApp QR Code" class="w-48 h-48" />
        <p class="text-xs text-n-slate-11">
          {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.SESSION.QR_HINT') }}
        </p>
      </div>

      <div
        v-if="!qrCode && !isConnected"
        class="text-sm text-n-slate-11 text-center py-4"
      >
        {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.SESSION.WAITING') }}
        <span class="animate-pulse">...</span>
      </div>

      <!-- Webhook URL -->
      <div class="p-4 bg-n-slate-1 rounded-lg border border-n-slate-3">
        <p class="font-semibold text-sm mb-1">
          {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.WEBHOOK_URL.LABEL') }}
        </p>
        <p class="text-xs text-n-slate-11 mb-2">
          {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.WEBHOOK_URL.DESC') }}
        </p>
        <div class="flex items-center gap-2">
          <code class="text-xs bg-n-slate-2 px-2 py-1 rounded flex-1 break-all">
            {{ webhookUrl }}
          </code>
          <NextButton size="small" @click="copyWebhookUrl">
            {{ $t('INBOX_MGMT.ADD.WAHA_CHANNEL.WEBHOOK_URL.COPY') }}
          </NextButton>
        </div>
      </div>

      <div class="flex gap-2">
        <NextButton
          solid
          blue
          :label="$t('INBOX_MGMT.ADD.WAHA_CHANNEL.PROCEED_BUTTON')"
          @click="proceed"
        />
        <NextButton
          :is-loading="isCancelling"
          :label="$t('INBOX_MGMT.ADD.WAHA_CHANNEL.CANCEL_BUTTON')"
          @click="cancel"
        />
      </div>
    </div>
  </div>
</template>
