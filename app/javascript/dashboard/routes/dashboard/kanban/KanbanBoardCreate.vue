<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import camelcaseKeys from 'camelcase-keys';

import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import Button from 'dashboard/components-next/button/Button.vue';
import { apiErrorMessage } from 'dashboard/helper/kanbanApiError';
import KanbanBoardTemplatePicker from './KanbanBoardTemplatePicker.vue';

// The blank template is the only one without a name of its own, so it is the one
// case that always has to ask the user for one.
const BLANK_TEMPLATE_KEY = 'blank';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();

const boards = useMapGetter('kanbanBoards/kanbanBoards');

const isLoading = ref(true);
const isCreating = ref(false);
const loadError = ref('');

const templates = ref([]);

const showNameDialog = ref(false);
const pendingTemplateKey = ref('');
const nameValue = ref('');
const nameError = ref('');

const trimmedName = computed(() => nameValue.value.trim());
// The board list comes from policy_scope, which resolves from scope.active, so it
// already holds exactly the boards the name uniqueness is scoped to.
const isNameTaken = name =>
  boards.value.some(
    board => board.name?.trim().toLowerCase() === name.trim().toLowerCase()
  );
const isNameDuplicate = computed(
  () => !!trimmedName.value && isNameTaken(trimmedName.value)
);
const confirmDisabled = computed(
  () => !trimmedName.value || isNameDuplicate.value || isCreating.value
);

const backDestination = computed(() => ({
  name: 'kanban_boards',
  params: { accountId: route.params.accountId },
}));

const goBack = () => router.push(backDestination.value);

const openNameDialog = (templateKey, suggestedName) => {
  pendingTemplateKey.value = templateKey;
  nameValue.value = suggestedName;
  nameError.value = '';
  showNameDialog.value = true;
};

const closeNameDialog = () => {
  if (isCreating.value) return;

  showNameDialog.value = false;
  pendingTemplateKey.value = '';
  nameValue.value = '';
  nameError.value = '';
};

const createBoard = async (templateKey, name) => {
  if (isCreating.value) return;

  isCreating.value = true;
  loadError.value = '';
  nameError.value = '';

  try {
    const response = await KanbanBoardsAPI.create({
      template_key: templateKey,
      kanban_board: { name, position: boards.value.length },
    });
    const created = camelcaseKeys(response.data || {}, { deep: true });

    await store.dispatch('kanbanBoards/refreshBoards');
    await router.replace({
      name: 'kanban_board_show',
      params: { accountId: route.params.accountId, boardId: created.id },
    });
    useAlert(t('KANBAN.BOARD_TEMPLATES.CREATE_SUCCESS'));
  } catch (error) {
    const message = apiErrorMessage(error, t('KANBAN.BOARD_EDIT.CREATE_ERROR'));
    if (showNameDialog.value) nameError.value = message;
    else loadError.value = message;
  } finally {
    isCreating.value = false;
  }
};

const onSelectTemplate = templateKey => {
  const template = templates.value.find(item => item.key === templateKey);
  const suggestedName =
    templateKey === BLANK_TEMPLATE_KEY ? '' : template?.name || '';

  if (!suggestedName || isNameTaken(suggestedName)) {
    openNameDialog(templateKey, suggestedName);
    return;
  }

  createBoard(templateKey, suggestedName);
};

const confirmName = () => {
  if (confirmDisabled.value) return;

  createBoard(pendingTemplateKey.value, trimmedName.value);
};

onMounted(async () => {
  try {
    const [response] = await Promise.all([
      KanbanBoardsAPI.templates(),
      store.dispatch('kanbanBoards/fetchBoards'),
    ]);
    templates.value = camelcaseKeys(response.data || [], { deep: true });
  } catch (error) {
    loadError.value = apiErrorMessage(
      error,
      t('KANBAN.BOARD_TEMPLATES.LOAD_ERROR')
    );
  } finally {
    isLoading.value = false;
  }
});
</script>

<template>
  <main
    class="flex h-full min-h-0 w-full flex-col bg-n-surface-1 text-n-slate-12"
  >
    <header
      class="flex flex-none items-center gap-4 border-b border-n-weak px-6 py-4"
    >
      <Button
        data-testid="kanban-board-create-back"
        icon="i-lucide-chevron-left"
        variant="ghost"
        color="slate"
        size="md"
        class="[&>span]:size-5"
        :aria-label="t('KANBAN.ACTIONS.BACK_TO_OVERVIEW')"
        :title="t('KANBAN.ACTIONS.BACK_TO_OVERVIEW')"
        @click="goBack"
      />
    </header>

    <div
      v-if="isLoading"
      data-testid="kanban-board-create-loading"
      class="flex flex-1 items-center justify-center text-sm text-n-slate-11"
    >
      {{ t('KANBAN.BOARD_EDIT.LOADING') }}
    </div>

    <template v-else>
      <p
        v-if="loadError"
        data-testid="kanban-board-template-picker-error"
        class="flex-none border-b border-n-weak bg-n-amber-2 px-6 py-2 text-sm text-n-amber-11"
      >
        {{ loadError }}
      </p>
      <div class="flex min-h-0 flex-1 flex-col overflow-y-auto">
        <KanbanBoardTemplatePicker
          :templates="templates"
          :is-creating="isCreating"
          @select="onSelectTemplate"
        />
      </div>
    </template>

    <woot-modal
      v-model:show="showNameDialog"
      :on-close="closeNameDialog"
      :show-close-button="false"
      size="modal-narrow"
    >
      <div
        class="flex w-full flex-col gap-4 rounded-lg bg-n-surface-1 p-6 text-n-slate-12"
        data-testid="kanban-board-create-name-modal"
      >
        <h2 class="text-base font-semibold">
          {{ t('KANBAN.BOARD_TEMPLATES.NAME_DIALOG.TITLE') }}
        </h2>

        <label class="grid gap-1 text-sm font-medium">
          {{ t('KANBAN.BOARD_TEMPLATES.NAME_DIALOG.LABEL') }}
          <input
            v-model="nameValue"
            data-testid="kanban-board-create-name-input"
            type="text"
            :placeholder="t('KANBAN.BOARD_EDIT.NEW_BOARD_DEFAULT_NAME')"
            class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
            @keyup.enter="confirmName"
          />
        </label>

        <p
          v-if="isNameDuplicate"
          data-testid="kanban-board-create-name-taken"
          class="text-sm text-n-ruby-11"
        >
          {{ t('KANBAN.BOARD_TEMPLATES.NAME_DIALOG.NAME_TAKEN') }}
        </p>
        <p
          v-else-if="nameError"
          data-testid="kanban-board-create-name-error"
          class="text-sm text-n-ruby-11"
        >
          {{ nameError }}
        </p>

        <div class="flex justify-end gap-2">
          <Button
            type="button"
            variant="outline"
            color="slate"
            size="sm"
            :label="t('KANBAN.ACTIONS.CANCEL')"
            :disabled="isCreating"
            @click="closeNameDialog"
          />
          <Button
            type="button"
            data-testid="kanban-board-create-name-confirm"
            color="blue"
            size="sm"
            :label="t('KANBAN.BOARD_TEMPLATES.NAME_DIALOG.CONFIRM')"
            :disabled="confirmDisabled"
            :is-loading="isCreating"
            @click="confirmName"
          />
        </div>
      </div>
    </woot-modal>
  </main>
</template>
