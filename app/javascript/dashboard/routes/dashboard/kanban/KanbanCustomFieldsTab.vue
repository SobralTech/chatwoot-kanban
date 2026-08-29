<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';
import { debounce } from '@chatwoot/utils';

import { useAlert } from 'dashboard/composables';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import { apiErrorMessage } from 'dashboard/helper/kanbanApiError';

const props = defineProps({
  boardId: { type: [Number, String], required: true },
});

const { t } = useI18n();

const fieldTypeOptions = computed(() => [
  { value: 'text', label: t('KANBAN.CUSTOM_FIELDS.TYPES.TEXT') },
  { value: 'number', label: t('KANBAN.CUSTOM_FIELDS.TYPES.NUMBER') },
  { value: 'date', label: t('KANBAN.CUSTOM_FIELDS.TYPES.DATE') },
  { value: 'boolean', label: t('KANBAN.CUSTOM_FIELDS.TYPES.BOOLEAN') },
]);

const multipleOptions = computed(() => [
  { value: false, label: t('KANBAN.CUSTOM_FIELDS.MULTIPLE_OPTIONS.SINGLE') },
  { value: true, label: t('KANBAN.CUSTOM_FIELDS.MULTIPLE_OPTIONS.LIST') },
]);

const isLoading = ref(false);
const loadError = ref('');
const fields = ref([]);

let localIdCounter = 0;
const nextLocalId = () => {
  localIdCounter += 1;
  return `new-${localIdCounter}`;
};

const buildRow = (payload = {}) => ({
  localId: payload.id ?? nextLocalId(),
  id: payload.id ?? null,
  key: payload.key ?? '',
  fieldType: payload.fieldType ?? 'text',
  multiple: payload.multiple ?? false,
  position: payload.position ?? 0,
  error: '',
  isSaving: false,
  isDeleting: false,
});

const fetchFields = async () => {
  isLoading.value = true;
  loadError.value = '';

  try {
    const response = await KanbanBoardsAPI.getCustomFields(props.boardId);
    const data = camelcaseKeys(response.data || [], { deep: true });
    fields.value = data
      .slice()
      .sort((a, b) => a.position - b.position)
      .map(buildRow);
  } catch (error) {
    loadError.value = apiErrorMessage(
      error,
      t('KANBAN.CUSTOM_FIELDS.LOAD_ERROR')
    );
    useAlert(loadError.value);
  } finally {
    isLoading.value = false;
  }
};

const buildPayload = row => ({
  custom_field: {
    key: row.key.trim(),
    field_type: row.fieldType,
    multiple: row.multiple,
  },
});

const createField = async row => {
  const key = row.key.trim();
  if (!key || row.id || row.isSaving) return;

  row.isSaving = true;
  row.error = '';

  try {
    const response = await KanbanBoardsAPI.createCustomField(
      props.boardId,
      buildPayload(row)
    );
    const created = camelcaseKeys(response.data, { deep: true });
    row.id = created.id;
    row.position = created.position;
  } catch (error) {
    row.error = apiErrorMessage(error, t('KANBAN.CUSTOM_FIELDS.CREATE_ERROR'));
    useAlert(row.error);
  } finally {
    row.isSaving = false;
  }
};

const updateField = async row => {
  if (!row.id || !row.key.trim()) return;

  row.isSaving = true;
  row.error = '';

  try {
    await KanbanBoardsAPI.updateCustomField(
      props.boardId,
      row.id,
      buildPayload(row)
    );
  } catch (error) {
    row.error = apiErrorMessage(error, t('KANBAN.CUSTOM_FIELDS.UPDATE_ERROR'));
    useAlert(row.error);
  } finally {
    row.isSaving = false;
  }
};

const debouncedUpdatersByRow = new Map();
const getDebouncedUpdate = row => {
  if (!debouncedUpdatersByRow.has(row.localId)) {
    debouncedUpdatersByRow.set(
      row.localId,
      debounce(rowToUpdate => updateField(rowToUpdate), 500, false)
    );
  }
  return debouncedUpdatersByRow.get(row.localId);
};

const onKeyInput = row => {
  if (!row.id) return;
  getDebouncedUpdate(row)(row);
};

const onKeyBlur = row => {
  if (!row.key.trim()) return;

  if (row.id) {
    updateField(row);
  } else {
    createField(row);
  }
};

const onTypeChange = (row, value) => {
  row.fieldType = value;
  if (row.id) updateField(row);
};

const onMultipleChange = (row, value) => {
  row.multiple = value;
  if (row.id) updateField(row);
};

const addRow = () => {
  fields.value.push(buildRow());
};

const removeRow = async row => {
  if (row.isDeleting) return;

  if (!row.id) {
    fields.value = fields.value.filter(item => item.localId !== row.localId);
    return;
  }

  row.isDeleting = true;
  row.error = '';

  try {
    await KanbanBoardsAPI.deleteCustomField(props.boardId, row.id);
    fields.value = fields.value.filter(item => item.localId !== row.localId);
  } catch (error) {
    row.error = apiErrorMessage(error, t('KANBAN.CUSTOM_FIELDS.DELETE_ERROR'));
    useAlert(row.error);
  } finally {
    row.isDeleting = false;
  }
};

onMounted(fetchFields);
</script>

<template>
  <div class="grid gap-5">
    <header class="flex flex-wrap items-start justify-between gap-3">
      <div class="min-w-0">
        <h2 class="mb-0 text-base font-medium text-n-slate-12">
          {{ t('KANBAN.CUSTOM_FIELDS.TITLE') }}
        </h2>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('KANBAN.CUSTOM_FIELDS.DESCRIPTION') }}
        </p>
      </div>
      <Button
        data-testid="kanban-custom-fields-add"
        icon="i-lucide-plus"
        :label="t('KANBAN.CUSTOM_FIELDS.ADD_FIELD')"
        color="slate"
        size="sm"
        @click="addRow"
      />
    </header>
    <div
      v-if="isLoading"
      data-testid="kanban-custom-fields-loading"
      class="flex items-center justify-center py-10 text-sm text-n-slate-11"
    >
      {{ t('KANBAN.CUSTOM_FIELDS.LOADING') }}
    </div>

    <div
      v-else-if="loadError"
      data-testid="kanban-custom-fields-load-error"
      class="rounded-lg border border-n-weak bg-n-surface-2 p-6 text-sm text-n-ruby-11"
    >
      {{ loadError }}
    </div>

    <template v-else>
      <p
        v-if="fields.length === 0"
        data-testid="kanban-custom-fields-empty"
        class="rounded-md border border-dashed border-n-weak px-3 py-4 text-sm text-n-slate-11"
      >
        {{ t('KANBAN.CUSTOM_FIELDS.EMPTY') }}
      </p>

      <div v-else class="grid gap-2">
        <div
          v-for="row in fields"
          :key="row.localId"
          data-testid="kanban-custom-field-row"
          class="grid gap-1"
        >
          <div
            class="flex flex-wrap items-center gap-2 rounded-md border border-n-weak bg-n-surface-2 px-3 py-2"
          >
            <input
              v-model="row.key"
              data-testid="kanban-custom-field-key"
              type="text"
              :placeholder="t('KANBAN.CUSTOM_FIELDS.KEY_PLACEHOLDER')"
              class="min-w-40 flex-1 !mb-0"
              @input="onKeyInput(row)"
              @blur="onKeyBlur(row)"
            />

            <Select
              data-testid="kanban-custom-field-type"
              :model-value="row.fieldType"
              :options="fieldTypeOptions"
              @update:model-value="value => onTypeChange(row, value)"
            />

            <Select
              data-testid="kanban-custom-field-multiple"
              :model-value="row.multiple"
              :options="multipleOptions"
              @update:model-value="value => onMultipleChange(row, value)"
            />

            <Button
              data-testid="kanban-custom-field-remove"
              icon="i-lucide-x"
              variant="ghost"
              color="ruby"
              size="sm"
              :is-loading="row.isDeleting"
              :title="t('KANBAN.CUSTOM_FIELDS.REMOVE_FIELD')"
              @click="removeRow(row)"
            />
          </div>

          <p
            v-if="row.error"
            data-testid="kanban-custom-field-error"
            class="text-sm text-n-ruby-11"
          >
            {{ row.error }}
          </p>
        </div>
      </div>
    </template>
  </div>
</template>
