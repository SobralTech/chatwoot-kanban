<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import camelcaseKeys from 'camelcase-keys';
import {
  addMonths,
  addWeeks,
  eachDayOfInterval,
  endOfWeek,
  isSameMonth,
  startOfMonth,
  startOfWeek,
} from 'date-fns';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import {
  monthGridRange,
  useKanbanAgendaData,
} from 'dashboard/composables/useKanbanAgendaData';
import { DEFAULT_KANBAN_STAGE_COLOR } from 'dashboard/helper/kanbanStageColors';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import KanbanAgendaCalendar from './agenda/KanbanAgendaCalendar.vue';
import KanbanAgendaCardPicker from './agenda/KanbanAgendaCardPicker.vue';
import KanbanOpportunityPanel from './opportunity/KanbanOpportunityPanel.vue';
import KanbanOpportunityPicker from './KanbanOpportunityPicker.vue';
import KanbanBoardViewShell from './board/KanbanBoardViewShell.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const boards = useMapGetter('kanbanBoards/kanbanBoards');

const board = ref(null);
const viewMode = ref('month');
const referenceDate = ref(new Date());
const weekStart = ref(startOfWeek(new Date()));
const selectedCardId = ref(null);
const isNoDateListOpen = ref(false);
const cardPendingRemoval = ref(null);
const showRemoveCardConfirmation = ref(false);
const selectedAgendaDate = ref(null);
const agendaCreateMode = ref(null);

const boardId = computed(() => Number(route.params.boardId));

const {
  cardsByDay,
  cardsWithoutDate,
  fetchMonth,
  fetchMore,
  fetchWithoutDate,
  hasMoreWithoutDate,
  isLoading,
  isLoadingWithoutDate,
  withoutDateCount,
} = useKanbanAgendaData({ boardId });

const VIEW_MODES = [
  { key: 'month', label: 'KANBAN.AGENDA.MONTH' },
  { key: 'week', label: 'KANBAN.AGENDA.WEEK' },
];

const isWeekMode = computed(() => viewMode.value === 'week');
const stages = computed(() => board.value?.stages || []);
const manualCreationStage = computed(() =>
  stages.value.find(
    stage =>
      stage.id !== board.value?.wonStageId &&
      stage.id !== board.value?.lostStageId
  )
);
const stageColors = computed(() =>
  Object.fromEntries(
    stages.value.map(stage => [
      stage.id,
      stage.color || DEFAULT_KANBAN_STAGE_COLOR,
    ])
  )
);

const chunkIntoWeeks = days =>
  days.reduce((weeks, day, index) => {
    if (index % 7 === 0) weeks.push([]);
    weeks[weeks.length - 1].push(day);
    return weeks;
  }, []);

const monthWeeks = computed(() => {
  const { from, to } = monthGridRange(referenceDate.value);
  return chunkIntoWeeks(eachDayOfInterval({ start: from, end: to }));
});

const visibleWeeks = computed(() =>
  isWeekMode.value
    ? [
        eachDayOfInterval({
          start: weekStart.value,
          end: endOfWeek(weekStart.value),
        }),
      ]
    : monthWeeks.value
);

const periodLabel = computed(() => {
  if (!isWeekMode.value) {
    return referenceDate.value.toLocaleDateString(undefined, {
      month: 'long',
      year: 'numeric',
    });
  }

  const options = { day: 'numeric', month: 'short' };
  const start = weekStart.value.toLocaleDateString(undefined, options);
  const end = endOfWeek(weekStart.value).toLocaleDateString(undefined, options);

  return `${start} – ${end}`;
});

// The month request covers the whole rendered grid, so a week that starts
// inside the loaded month is already in memory and asks for nothing.
const showMonth = async date => {
  if (isSameMonth(date, referenceDate.value)) return;

  referenceDate.value = date;
  await fetchMonth(date);
};

const goToPeriod = async direction => {
  if (isWeekMode.value) {
    weekStart.value = addWeeks(weekStart.value, direction);
    await showMonth(weekStart.value);
    return;
  }

  const nextMonth = addMonths(referenceDate.value, direction);
  referenceDate.value = nextMonth;
  await fetchMonth(nextMonth);
};

const goToToday = async () => {
  const today = new Date();
  weekStart.value = startOfWeek(today);
  await showMonth(today);
};

// Week mode always opens on a week the loaded month already covers, so
// switching to it from a month the user browsed to never shows an empty week.
const setViewMode = mode => {
  viewMode.value = mode;
  if (mode !== 'week') return;

  const today = new Date();
  weekStart.value = startOfWeek(
    isSameMonth(today, referenceDate.value)
      ? today
      : startOfMonth(referenceDate.value)
  );
};

const openCard = card => {
  selectedCardId.value = card.id;
};

const refreshAgenda = () =>
  Promise.all([
    fetchMonth(referenceDate.value),
    fetchWithoutDate({ reset: true }),
  ]);

const openAgendaCreate = (mode, date) => {
  selectedAgendaDate.value = date;
  agendaCreateMode.value = mode;
};

const closeAgendaCreate = () => {
  agendaCreateMode.value = null;
  selectedAgendaDate.value = null;
};

const selectedDueAt = computed(() => selectedAgendaDate.value?.toISOString());

const onManualCardCreated = async () => {
  closeAgendaCreate();
  useAlert(t('KANBAN.ADD_ITEM.CREATE_SUCCESS'));
  await refreshAgenda();
};

const scheduleExistingCard = async card => {
  try {
    await KanbanBoardsAPI.updateCardDetailsById(boardId.value, card.id, {
      due_at: selectedDueAt.value,
    });
    closeAgendaCreate();
    await refreshAgenda();
    useAlert(t('KANBAN.CARD.DUE_DATE_UPDATE_SUCCESS'));
  } catch (error) {
    closeAgendaCreate();
    useAlert(t('KANBAN.CARD.DUE_DATE_UPDATE_ERROR'));
  }
};

const fetchBoard = async () => {
  const response = await KanbanBoardsAPI.showBoard(boardId.value);
  board.value = camelcaseKeys(response.data, { deep: true });
};

const loadAgenda = async () => {
  try {
    await Promise.all([
      fetchBoard(),
      fetchMonth(referenceDate.value),
      fetchWithoutDate({ reset: true }),
    ]);
  } catch (error) {
    useAlert(t('KANBAN.ERROR'));
  }
};

const moveCardToStage = async (card, targetStageId) => {
  try {
    await KanbanBoardsAPI.reorderCardById(boardId.value, card.id, {
      card: { kanban_stage_id: Number(targetStageId), after_card_id: null },
    });
    await refreshAgenda();
    return true;
  } catch (error) {
    useAlert(t('KANBAN.ACTIONS.REORDER_CARD_ERROR'));
    return false;
  }
};

const closeCardDetails = () => {
  selectedCardId.value = null;
};

const exitThen = action => {
  closeCardDetails();
  action?.();
};

const conversationPath = card =>
  frontendURL(
    conversationUrl({
      accountId: route.params.accountId,
      id: card.conversationId,
    }),
    { card_id: card.id }
  );

const openConversation = card => {
  if (!card?.conversationId) return;

  exitThen(() => router.push(conversationPath(card)));
};

const openConversationInNewTab = card => {
  if (!card?.conversationId) return;

  exitThen(() =>
    window.open(
      `${window.chatwootConfig.hostURL}${conversationPath(card)}`,
      '_blank',
      'noopener,noreferrer'
    )
  );
};

const openCardInFunnel = card => {
  exitThen(() =>
    router.push({
      name: 'kanban_board_show',
      params: { accountId: route.params.accountId, boardId: boardId.value },
      query: { card_id: card.id },
    })
  );
};

const copyCardLink = async card => {
  const path = frontendURL(
    `accounts/${route.params.accountId}/kanban/${boardId.value}`,
    { card_id: card.id }
  );
  await copyTextToClipboard(`${window.chatwootConfig.hostURL}${path}`);
  useAlert(t('KANBAN.OPPORTUNITY_DETAILS.CARD_LINK_COPIED'));
};

const onBoardChanged = ({ boardName } = {}) => {
  closeCardDetails();
  refreshAgenda();
  useAlert(
    t('KANBAN.CARD.MOVE_BOARD_SUCCESS', {
      board: boardName || t('KANBAN.NO_BOARD_SELECTED'),
    })
  );
};

const openRemoveCardConfirmation = card => {
  closeCardDetails();
  cardPendingRemoval.value = card;
  showRemoveCardConfirmation.value = true;
};

const closeRemoveCardConfirmation = () => {
  showRemoveCardConfirmation.value = false;
  cardPendingRemoval.value = null;
};

const confirmRemoveCard = async () => {
  const card = cardPendingRemoval.value;
  closeRemoveCardConfirmation();
  if (!card) return;

  try {
    await KanbanBoardsAPI.deleteCardById(boardId.value, card.id);
    await refreshAgenda();
    useAlert(t('KANBAN.ACTIONS.REMOVE_CARD_SUCCESS'));
  } catch (error) {
    useAlert(t('KANBAN.ACTIONS.REMOVE_CARD_ERROR'));
  }
};

const cardTitle = card =>
  card.subject || card.contact?.name || t('KANBAN.CARD.UNKNOWN_CONTACT');

onMounted(loadAgenda);
</script>

<template>
  <KanbanBoardViewShell>
    <div
      class="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto p-4 md:p-6"
      data-testid="kanban-agenda"
    >
      <div
        class="flex flex-col gap-2 lg:flex-row lg:items-center lg:justify-between"
      >
        <div class="flex items-center gap-1">
          <NextButton
            icon="i-lucide-chevron-left"
            variant="ghost"
            color="slate"
            size="sm"
            :aria-label="t('KANBAN.AGENDA.PREVIOUS')"
            data-testid="kanban-agenda-previous"
            @click="goToPeriod(-1)"
          />
          <span
            class="min-w-40 text-center text-base font-semibold capitalize text-n-slate-12"
          >
            {{ periodLabel }}
          </span>
          <NextButton
            icon="i-lucide-chevron-right"
            variant="ghost"
            color="slate"
            size="sm"
            :aria-label="t('KANBAN.AGENDA.NEXT')"
            data-testid="kanban-agenda-next"
            @click="goToPeriod(1)"
          />
          <NextButton
            :label="t('KANBAN.AGENDA.TODAY')"
            variant="faded"
            color="slate"
            size="sm"
            data-testid="kanban-agenda-today"
            @click="goToToday"
          />
        </div>

        <div class="flex items-center gap-1 rounded-lg bg-n-solid-2 p-1">
          <button
            v-for="mode in VIEW_MODES"
            :key="mode.key"
            type="button"
            class="rounded-md px-3 py-1 text-sm font-medium"
            :class="
              viewMode === mode.key
                ? 'bg-n-brand/10 text-n-brand'
                : 'text-n-slate-11 hover:bg-n-alpha-2'
            "
            :data-testid="`kanban-agenda-mode-${mode.key}`"
            @click="setViewMode(mode.key)"
          >
            {{ t(mode.label) }}
          </button>
        </div>
      </div>

      <div
        class="flex flex-wrap items-center gap-x-4 gap-y-1"
        data-testid="kanban-agenda-legend"
      >
        <span
          v-for="stage in stages"
          :key="stage.id"
          class="flex items-center gap-1.5 text-xs text-n-slate-11"
        >
          <span
            class="size-2.5 flex-shrink-0 rounded-full"
            :style="{
              backgroundColor: stage.color || DEFAULT_KANBAN_STAGE_COLOR,
            }"
            aria-hidden="true"
          />
          {{ stage.name }}
        </span>
      </div>

      <KanbanAgendaCalendar
        :weeks="visibleWeeks"
        :reference-date="referenceDate"
        :cards-by-day="cardsByDay"
        :stage-colors="stageColors"
        :is-week-mode="isWeekMode"
        :class="{ 'opacity-50': isLoading }"
        @card-click="openCard"
        @create-new="openAgendaCreate('create', $event)"
        @schedule-existing="openAgendaCreate('schedule', $event)"
      />

      <section
        class="rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container"
        data-testid="kanban-agenda-no-date"
      >
        <button
          type="button"
          class="flex w-full items-center justify-between gap-2 text-sm font-medium text-n-slate-12"
          @click="isNoDateListOpen = !isNoDateListOpen"
        >
          <span class="flex items-center gap-2">
            <span>{{ t('KANBAN.AGENDA.NO_DATE_ITEMS') }}</span>
            <span
              class="rounded-full bg-n-alpha-2 px-2 text-xs text-n-slate-11"
              data-testid="kanban-agenda-no-date-count"
            >
              {{ withoutDateCount }}
            </span>
          </span>
          <i
            class="size-4"
            :class="
              isNoDateListOpen ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
            "
          />
        </button>

        <div v-if="isNoDateListOpen" class="mt-3 flex flex-col gap-1">
          <button
            v-for="card in cardsWithoutDate"
            :key="card.id"
            type="button"
            class="flex items-center gap-2 rounded-md px-2 py-1.5 text-left hover:bg-n-alpha-2"
            :data-card-id="card.id"
            @click="openCard(card)"
          >
            <span
              class="size-2 flex-shrink-0 rounded-full"
              :style="{ backgroundColor: stageColors[card.kanbanStageId] }"
              aria-hidden="true"
            />
            <span class="truncate text-sm text-n-slate-12">
              {{ cardTitle(card) }}
            </span>
          </button>

          <NextButton
            v-if="hasMoreWithoutDate"
            :label="t('KANBAN.AGENDA.LOAD_MORE')"
            variant="link"
            color="slate"
            size="sm"
            :is-loading="isLoadingWithoutDate"
            class="self-start"
            @click="fetchMore"
          />
        </div>
      </section>
    </div>

    <KanbanOpportunityPanel
      v-if="selectedCardId && board"
      :board-id="boardId"
      :card-id="selectedCardId"
      :board-name="board.name"
      :board="board"
      :boards="boards"
      :stages="stages"
      :won-stage-id="board.wonStageId"
      :lost-stage-id="board.lostStageId"
      :lost-reason-required="!!board.lostReasonRequired"
      :reasons="board.reasons || []"
      :custom-fields="board.customFields || []"
      :move-to-stage="moveCardToStage"
      @close="closeCardDetails"
      @updated="refreshAgenda"
      @open-conversation="openConversation"
      @open-conversation-in-new-tab="openConversationInNewTab"
      @open-funnel="openCardInFunnel"
      @copy-card-link="copyCardLink"
      @board-changed="onBoardChanged"
      @remove-card="openRemoveCardConfirmation"
    />

    <woot-modal
      v-if="agendaCreateMode === 'create' && manualCreationStage"
      show
      :show-close-button="false"
      size="modal-narrow"
      :on-close="closeAgendaCreate"
    >
      <KanbanOpportunityPicker
        :kanban-board-id="boardId"
        :kanban-stage-id="manualCreationStage.id"
        :kanban-stage-name="manualCreationStage.name"
        :inbox-scope-mode="board.inboxScopeMode"
        :allowed-inbox-ids="board.allowedInboxIds"
        :initial-due-at="selectedDueAt"
        @created="onManualCardCreated"
        @close="closeAgendaCreate"
      />
    </woot-modal>

    <woot-modal
      v-if="agendaCreateMode === 'schedule'"
      show
      :show-close-button="false"
      size="modal-narrow"
      :on-close="closeAgendaCreate"
    >
      <KanbanAgendaCardPicker
        :board-id="boardId"
        @close="closeAgendaCreate"
        @scheduled="scheduleExistingCard"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showRemoveCardConfirmation"
      :on-close="closeRemoveCardConfirmation"
      :on-confirm="confirmRemoveCard"
      :title="t('KANBAN.REMOVE_CARD.TITLE')"
      :message="t('KANBAN.REMOVE_CARD.MESSAGE')"
      :message-value="cardPendingRemoval ? cardTitle(cardPendingRemoval) : ''"
      :confirm-text="t('KANBAN.REMOVE_CARD.CONFIRM')"
      :reject-text="t('KANBAN.REMOVE_CARD.CANCEL')"
    />
  </KanbanBoardViewShell>
</template>
