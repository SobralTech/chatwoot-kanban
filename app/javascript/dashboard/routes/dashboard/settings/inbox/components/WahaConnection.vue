<script setup>
/* global axios */
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SpinnerLoader from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const { accountId } = useAccount();

const sessionStatus = ref('');
const phoneNumber = ref('');
const statusHistory = ref([]);
const qrCode = ref('');

const showModal = ref(false);
const modalOpenedAt = ref(0);
const modalSuccess = ref(false);
const modalMismatch = ref(false);

let tabPollInterval = null;
let modalPollInterval = null;

const statusUrl = computed(
  () =>
    `/api/v1/accounts/${accountId.value}/inboxes/${props.inbox.id}/waha_session_status`
);
const reconnectUrl = computed(
  () =>
    `/api/v1/accounts/${accountId.value}/inboxes/${props.inbox.id}/waha_reconnect`
);

const isConnected = computed(() => sessionStatus.value === 'WORKING');
const canReconnect = computed(() => sessionStatus.value !== 'WORKING');

const displayStatus = computed(() => {
  if (!sessionStatus.value) return '';
  const key = `INBOX_MGMT.ADD.WAHA_CHANNEL.SESSION.STATUSES.${sessionStatus.value}`;
  const translated = t(key);
  return translated === key ? sessionStatus.value : translated;
});

const statusColorClass = computed(() => {
  if (sessionStatus.value === 'WORKING') return 'text-n-teal-11';
  if (['STARTING', 'SCAN_QR_CODE'].includes(sessionStatus.value))
    return 'text-n-amber-11';
  return 'text-n-ruby-11';
});

// Most recent event first.
const sortedLog = computed(() => [...statusHistory.value].reverse());

function eventLabel(status) {
  const key = `INBOX_MGMT.WAHA_CONNECTION.EVENTS.${status}`;
  const translated = t(key);
  return translated === key ? status : translated;
}

function formatTimestamp(timestamp) {
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(timestamp));
}

async function fetchStatus() {
  try {
    const { data } = await axios.get(statusUrl.value);
    sessionStatus.value = data.status || '';
    phoneNumber.value = data.phone_number || '';
    statusHistory.value = data.status_history || [];
    qrCode.value = data.qr_code || '';
  } catch {
    // silently ignore poll errors
  }
}

// A mismatch is signalled by a synthetic NUMBER_MISMATCH_BLOCKED event logged
// after the modal was opened for this reconnection attempt.
function detectMismatch() {
  const lastEvent = statusHistory.value[statusHistory.value.length - 1];
  if (!lastEvent || lastEvent.status !== 'NUMBER_MISMATCH_BLOCKED') return;
  if (new Date(lastEvent.timestamp).getTime() >= modalOpenedAt.value) {
    modalMismatch.value = true;
  }
}

function stopModalPolling() {
  if (modalPollInterval) {
    clearInterval(modalPollInterval);
    modalPollInterval = null;
  }
}

async function pollModal() {
  await fetchStatus();
  if (isConnected.value) {
    modalSuccess.value = true;
    stopModalPolling();
    return;
  }
  detectMismatch();
}

async function openReconnectModal() {
  modalSuccess.value = false;
  modalMismatch.value = false;
  modalOpenedAt.value = Date.now();
  showModal.value = true;

  try {
    await axios.post(reconnectUrl.value);
  } catch {
    // ignore — the modal polling will surface the resulting state
  }

  await pollModal();
  modalPollInterval = setInterval(pollModal, 10000);
}

function closeModal() {
  stopModalPolling();
  showModal.value = false;
}

onMounted(() => {
  fetchStatus();
  tabPollInterval = setInterval(fetchStatus, 5000);
});

onUnmounted(() => {
  if (tabPollInterval) clearInterval(tabPollInterval);
  stopModalPolling();
});
</script>

<template>
  <div class="flex flex-col gap-6 max-w-2xl">
    <!-- Current status card -->
    <div
      class="flex flex-col gap-2 p-4 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
    >
      <div class="flex items-center justify-between gap-3">
        <div class="flex flex-col gap-1">
          <span class="text-heading-3 text-n-slate-12">
            {{ $t('INBOX_MGMT.WAHA_CONNECTION.STATUS_TITLE') }}
          </span>
          <span class="text-body-main font-semibold" :class="statusColorClass">
            {{ displayStatus }}
          </span>
          <span v-if="phoneNumber" class="text-body-main text-n-slate-11">
            {{ $t('INBOX_MGMT.WAHA_CONNECTION.PHONE_NUMBER_LABEL') }}:
            {{ phoneNumber }}
          </span>
        </div>
        <NextButton
          v-if="canReconnect"
          solid
          blue
          sm
          :label="$t('INBOX_MGMT.WAHA_CONNECTION.RECONNECT_BUTTON')"
          @click="openReconnectModal"
        />
      </div>
    </div>

    <!-- Connection log -->
    <div class="flex flex-col gap-2">
      <span class="text-heading-3 text-n-slate-12">
        {{ $t('INBOX_MGMT.WAHA_CONNECTION.LOG_TITLE') }}
      </span>
      <p v-if="!sortedLog.length" class="text-body-main text-n-slate-11">
        {{ $t('INBOX_MGMT.WAHA_CONNECTION.LOG_EMPTY') }}
      </p>
      <ul
        v-else
        class="flex flex-col outline outline-1 -outline-offset-1 outline-n-weak rounded-xl divide-y divide-n-weak"
      >
        <li
          v-for="(event, index) in sortedLog"
          :key="index"
          class="flex items-center justify-between gap-3 px-4 py-2.5"
        >
          <span class="text-body-main text-n-slate-12">
            {{ eventLabel(event.status) }}
          </span>
          <span class="text-body-main text-n-slate-11">
            {{ formatTimestamp(event.timestamp) }}
          </span>
        </li>
      </ul>
    </div>

    <!-- Reconnect modal -->
    <woot-modal v-model:show="showModal" :on-close="closeModal">
      <div class="flex flex-col items-center gap-4 p-8">
        <h3 class="text-heading-2 text-n-slate-12">
          {{ $t('INBOX_MGMT.WAHA_CONNECTION.MODAL.TITLE') }}
        </h3>

        <div v-if="modalSuccess" class="flex flex-col items-center gap-4 py-4">
          <p class="text-body-main text-n-teal-11 text-center">
            {{ $t('INBOX_MGMT.WAHA_CONNECTION.MODAL.SUCCESS') }}
          </p>
          <NextButton
            solid
            blue
            :label="$t('INBOX_MGMT.WAHA_CONNECTION.MODAL.CLOSE_BUTTON')"
            @click="closeModal"
          />
        </div>

        <template v-else>
          <p
            v-if="modalMismatch"
            class="text-body-main text-n-ruby-11 text-center px-4 py-2 rounded-lg bg-n-ruby-3"
          >
            {{ $t('INBOX_MGMT.WAHA_CONNECTION.MODAL.NUMBER_MISMATCH') }}
          </p>

          <div v-if="qrCode" class="flex flex-col items-center gap-2">
            <p class="text-body-main font-semibold text-n-slate-12">
              {{ $t('INBOX_MGMT.WAHA_CONNECTION.MODAL.QR_LABEL') }}
            </p>
            <img :src="qrCode" alt="WhatsApp QR Code" class="w-48 h-48" />
            <p class="text-body-small text-n-slate-11 text-center">
              {{ $t('INBOX_MGMT.WAHA_CONNECTION.MODAL.QR_HINT') }}
            </p>
          </div>
          <div v-else class="flex flex-col items-center gap-2 py-6">
            <SpinnerLoader :size="24" class="text-n-blue-9" />
            <p class="text-body-main text-n-slate-11">
              {{ $t('INBOX_MGMT.WAHA_CONNECTION.MODAL.WAITING') }}
            </p>
          </div>
        </template>
      </div>
    </woot-modal>
  </div>
</template>
