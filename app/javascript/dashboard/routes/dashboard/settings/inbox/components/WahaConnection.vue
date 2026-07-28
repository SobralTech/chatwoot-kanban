<script setup>
/* global axios */
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { translateOrRaw } from 'dashboard/helper/inbox';
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
const importState = ref({});

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
const importRetryUrl = computed(
  () =>
    `/api/v1/accounts/${accountId.value}/inboxes/${props.inbox.id}/waha_import_retry`
);

const isConnected = computed(() => sessionStatus.value === 'WORKING');

const displayStatus = computed(() => {
  if (!sessionStatus.value) return '';
  return translateOrRaw(
    t,
    `INBOX_MGMT.ADD.WAHA_CHANNEL.SESSION.STATUSES.${sessionStatus.value}`,
    sessionStatus.value
  );
});

const statusColorClass = computed(() => {
  if (sessionStatus.value === 'WORKING') return 'text-n-teal-11';
  if (['STARTING', 'SCAN_QR_CODE'].includes(sessionStatus.value))
    return 'text-n-amber-11';
  return 'text-n-ruby-11';
});

// Most recent event first.
const sortedLog = computed(() => [...statusHistory.value].reverse());

// --- History import progress (shares the 5s status poll) ---
const importStatus = computed(() => importState.value.status);
// Any recorded status means an import has been kicked off for this channel.
const showImportProgress = computed(() => Boolean(importStatus.value));
const importTotal = computed(() => importState.value.total_chats || 0);
const importProcessed = computed(() => importState.value.processed_chats || 0);
const importMessages = computed(() => importState.value.imported_messages || 0);
// While no chats are counted yet the bar is indeterminate ("discovering…").
const isImportIndeterminate = computed(
  () => importStatus.value === 'pending' || importTotal.value === 0
);
const importPercent = computed(() =>
  isImportIndeterminate.value
    ? 0
    : Math.min(
        100,
        Math.round((importProcessed.value / importTotal.value) * 100)
      )
);
const importRunningLabel = computed(() =>
  importState.value.kind === 'gap_fill'
    ? t('INBOX_MGMT.WAHA_CONNECTION.IMPORT.GAP_FILL_RUNNING')
    : t('INBOX_MGMT.WAHA_CONNECTION.IMPORT.RUNNING')
);

function eventLabel(status) {
  return translateOrRaw(
    t,
    `INBOX_MGMT.WAHA_CONNECTION.EVENTS.${status}`,
    status
  );
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
    importState.value = data.import_state || {};
  } catch {
    // silently ignore poll errors
  }
}

async function retryImport() {
  try {
    await axios.post(importRetryUrl.value);
    await fetchStatus();
  } catch {
    // ignore — the status poll will surface the resulting state
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

function stopTabPolling() {
  if (tabPollInterval) {
    clearInterval(tabPollInterval);
    tabPollInterval = null;
  }
}

function startTabPolling() {
  stopTabPolling();
  tabPollInterval = setInterval(fetchStatus, 5000);
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
  // The modal drives its own polling; the tab poll would only duplicate it.
  stopTabPolling();

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
  startTabPolling();
}

onMounted(() => {
  fetchStatus();
  startTabPolling();
});

onUnmounted(() => {
  stopTabPolling();
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
          v-if="!isConnected"
          solid
          blue
          sm
          :label="$t('INBOX_MGMT.WAHA_CONNECTION.RECONNECT_BUTTON')"
          @click="openReconnectModal"
        />
      </div>
    </div>

    <!-- History import progress (below the connection status, per spec) -->
    <div
      v-if="showImportProgress"
      class="flex flex-col gap-2 p-4 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
    >
      <template v-if="importStatus === 'running' || importStatus === 'pending'">
        <div class="flex items-center justify-between gap-3">
          <span class="text-body-main text-n-slate-12">
            {{
              isImportIndeterminate
                ? $t('INBOX_MGMT.WAHA_CONNECTION.IMPORT.DISCOVERING')
                : importRunningLabel
            }}
          </span>
          <span
            v-if="!isImportIndeterminate"
            class="text-body-main text-n-slate-11 tabular-nums"
          >
            {{
              $t('INBOX_MGMT.WAHA_CONNECTION.IMPORT.PROGRESS', {
                processed: importProcessed,
                total: importTotal,
              })
            }}
          </span>
        </div>
        <div class="rounded-full overflow-hidden h-2 w-full bg-n-slate-4">
          <div
            class="h-2 bg-n-blue-9"
            :class="{ 'w-full animate-pulse': isImportIndeterminate }"
            :style="
              isImportIndeterminate ? null : { width: `${importPercent}%` }
            "
          />
        </div>
        <span
          v-if="!isImportIndeterminate"
          class="text-body-small text-n-slate-11"
        >
          {{
            $t('INBOX_MGMT.WAHA_CONNECTION.IMPORT.MESSAGES_IMPORTED', {
              count: importMessages,
            })
          }}
        </span>
      </template>

      <span
        v-else-if="importStatus === 'done'"
        class="text-body-small text-n-slate-11"
      >
        {{
          $t('INBOX_MGMT.WAHA_CONNECTION.IMPORT.DONE', {
            count: importMessages,
          })
        }}
      </span>

      <div v-else class="flex items-center justify-between gap-3">
        <span class="text-body-main text-n-ruby-11">
          {{ $t('INBOX_MGMT.WAHA_CONNECTION.IMPORT.FAILED') }}
        </span>
        <NextButton
          sm
          faded
          blue
          :label="$t('INBOX_MGMT.WAHA_CONNECTION.IMPORT.RETRY_BUTTON')"
          @click="retryImport"
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
