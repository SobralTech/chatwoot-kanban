<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const { t } = useI18n();

const cards = ref([]);
const isLoading = ref(false);
const hasError = ref(false);
const requestId = ref(0);
const abortController = ref(null);

const hasCards = computed(() => cards.value.length > 0);

const stageColorClass = color => {
  const colorClasses = {
    blue: 'bg-n-blue-9',
    teal: 'bg-n-teal-9',
    amber: 'bg-n-amber-9',
    ruby: 'bg-n-ruby-9',
    iris: 'bg-n-iris-9',
    violet: 'bg-n-violet-9',
  };

  return colorClasses[color] || 'bg-n-slate-9';
};

const isAbortError = error =>
  error?.name === 'AbortError' || error?.name === 'CanceledError';

const resetAbortController = () => {
  abortController.value?.abort();
  abortController.value = null;
};

const loadCards = async () => {
  if (!props.conversationId) return;

  const currentRequestId = requestId.value + 1;
  requestId.value = currentRequestId;
  resetAbortController();

  const controller = new AbortController();
  abortController.value = controller;
  isLoading.value = true;
  hasError.value = false;

  try {
    const response = await KanbanBoardsAPI.getConversationCards(
      props.conversationId,
      { signal: controller.signal }
    );

    if (requestId.value !== currentRequestId || controller.signal.aborted) {
      return;
    }

    cards.value = response.data?.payload || [];
  } catch (error) {
    if (isAbortError(error) || requestId.value !== currentRequestId) {
      return;
    }

    cards.value = [];
    hasError.value = true;
  } finally {
    if (requestId.value === currentRequestId) {
      isLoading.value = false;
      abortController.value = null;
    }
  }
};

onMounted(loadCards);

watch(() => props.conversationId, loadCards);

onBeforeUnmount(resetAbortController);
</script>

<template>
  <div class="p-3 text-sm">
    <p v-if="isLoading" class="mb-0 text-n-slate-11">
      {{ t('CONVERSATION_SIDEBAR.KANBAN.LOADING') }}
    </p>
    <p v-else-if="hasError" class="mb-0 text-n-ruby-11">
      {{ t('CONVERSATION_SIDEBAR.KANBAN.ERROR') }}
    </p>
    <p v-else-if="!hasCards" class="mb-0 text-n-slate-11">
      {{ t('CONVERSATION_SIDEBAR.KANBAN.EMPTY') }}
    </p>
    <ul v-else class="m-0 flex list-none flex-col gap-2 p-0">
      <li
        v-for="card in cards"
        :key="card.id"
        class="rounded-lg border border-n-weak bg-n-surface-1 p-3"
      >
        <p class="mb-1 truncate font-medium text-n-slate-12">
          {{ card.subject }}
        </p>
        <div class="flex min-w-0 items-center gap-2 text-xs text-n-slate-11">
          <span class="min-w-0 truncate">
            {{ card.kanban_board?.name }}
          </span>
          <span
            v-if="card.kanban_stage?.color"
            class="size-2 flex-shrink-0 rounded-full"
            :class="stageColorClass(card.kanban_stage.color)"
            aria-hidden="true"
          />
          <span class="min-w-0 truncate">
            {{ card.kanban_stage?.name }}
          </span>
        </div>
      </li>
    </ul>
  </div>
</template>
