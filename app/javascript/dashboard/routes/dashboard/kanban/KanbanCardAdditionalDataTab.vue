<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';

import { useAlert } from 'dashboard/composables';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import Button from 'dashboard/components-next/button/Button.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import { apiErrorMessage } from 'dashboard/helper/kanbanApiError';

const props = defineProps({
  boardId: { type: [Number, String], required: true },
  cardId: { type: [Number, String], required: true },
  customFields: { type: Array, default: () => [] },
});

const { t } = useI18n();

const isLoading = ref(props.customFields.length > 0);
const loadError = ref('');
const valuesByFieldId = reactive({});
const tagDrafts = reactive({});

const savedSnapshot = ref('');
const buildSnapshot = () => JSON.stringify(valuesByFieldId);
const captureSnapshot = () => {
  savedSnapshot.value = buildSnapshot();
};
// savedSnapshot stays empty until the values load, so a card in flight (or one
// whose values failed to load) never reports unsaved changes.
const hasUnsavedChanges = computed(
  () =>
    !!savedSnapshot.value &&
    props.customFields.length > 0 &&
    buildSnapshot() !== savedSnapshot.value
);

const isBooleanTrue = value => value === true || value === 'true';

const normalizeValues = (field, rawValues) => {
  const values = Array.isArray(rawValues) ? rawValues.slice() : [];

  if (field.fieldType === 'boolean') {
    return [isBooleanTrue(values[0])];
  }

  return values;
};

const fetchData = async () => {
  if (!props.customFields.length) {
    isLoading.value = false;
    return;
  }

  isLoading.value = true;
  loadError.value = '';

  try {
    const valuesResponse = await KanbanBoardsAPI.getCardFieldValues(
      props.boardId,
      props.cardId
    );

    const savedValues = camelcaseKeys(valuesResponse.data?.payload || [], {
      deep: true,
    });
    const valuesByFieldIdFromApi = savedValues.reduce((acc, item) => {
      acc[item.kanbanCustomFieldId] = item.value;
      return acc;
    }, {});

    props.customFields.forEach(field => {
      valuesByFieldId[field.id] = normalizeValues(
        field,
        valuesByFieldIdFromApi[field.id]
      );
      tagDrafts[field.id] = '';
    });

    captureSnapshot();
  } catch (error) {
    loadError.value = apiErrorMessage(
      error,
      t('KANBAN.CARD_ADDITIONAL_DATA.LOAD_ERROR')
    );
    useAlert(loadError.value);
  } finally {
    isLoading.value = false;
  }
};

const setSingleValue = (field, value) => {
  if (value === '' || value === null || value === undefined) {
    valuesByFieldId[field.id] = [];
    return;
  }
  valuesByFieldId[field.id] = [value];
};

const addTagValue = field => {
  const draft = (tagDrafts[field.id] || '').trim();
  if (!draft) return;

  if (field.fieldType === 'number') {
    const numericValue = Number(draft);
    if (Number.isNaN(numericValue)) return;
    valuesByFieldId[field.id].push(numericValue);
  } else {
    valuesByFieldId[field.id].push(draft);
  }

  tagDrafts[field.id] = '';
};

const removeTagValue = (field, index) => {
  valuesByFieldId[field.id].splice(index, 1);
};

const addDateValue = field => {
  valuesByFieldId[field.id].push('');
};

const removeDateValue = (field, index) => {
  valuesByFieldId[field.id].splice(index, 1);
};

const buildPayload = () => {
  const fieldValues = {};

  props.customFields.forEach(field => {
    const values = valuesByFieldId[field.id] || [];

    if (field.fieldType === 'boolean') {
      fieldValues[field.id] = [Boolean(values[0])];
    } else if (field.fieldType === 'date') {
      fieldValues[field.id] = values.filter(value => !!value);
    } else {
      fieldValues[field.id] = values.filter(
        value => value !== '' && value !== null && value !== undefined
      );
    }
  });

  return { field_values: fieldValues };
};

const saveFieldValues = async () => {
  try {
    await KanbanBoardsAPI.updateCardFieldValues(
      props.boardId,
      props.cardId,
      buildPayload()
    );
    captureSnapshot();
    useAlert(t('KANBAN.CARD_ADDITIONAL_DATA.SAVE_SUCCESS'));
    return true;
  } catch (error) {
    useAlert(
      apiErrorMessage(error, t('KANBAN.CARD_ADDITIONAL_DATA.SAVE_ERROR'))
    );
    return false;
  }
};

onMounted(fetchData);

defineExpose({ hasUnsavedChanges, saveFieldValues });
</script>

<template>
  <div class="grid gap-4">
    <div
      v-if="isLoading"
      data-testid="kanban-card-additional-data-loading"
      class="flex items-center justify-center py-10 text-sm text-n-slate-11"
    >
      {{ t('KANBAN.CARD_ADDITIONAL_DATA.LOADING') }}
    </div>

    <div
      v-else-if="loadError"
      data-testid="kanban-card-additional-data-load-error"
      class="rounded-lg border border-n-weak bg-n-surface-2 p-6 text-sm text-n-ruby-11"
    >
      {{ loadError }}
    </div>

    <template v-else>
      <div v-if="customFields.length" class="grid gap-4">
        <div
          v-for="field in customFields"
          :key="field.id"
          data-testid="kanban-card-additional-data-field"
          class="grid gap-1.5"
        >
          <!-- Boolean: always a single toggle, multiple is not applicable -->
          <div
            v-if="field.fieldType === 'boolean'"
            class="flex items-center gap-2"
          >
            <Switch v-model="valuesByFieldId[field.id][0]" />
            <span class="text-sm font-medium text-n-slate-12">{{
              field.key
            }}</span>
          </div>

          <template v-else-if="!field.multiple">
            <!-- Text / number / date, single value -->
            <NextInput
              :label="field.key"
              :type="field.fieldType === 'text' ? 'text' : field.fieldType"
              :model-value="valuesByFieldId[field.id][0] ?? ''"
              @update:model-value="value => setSingleValue(field, value)"
            />
          </template>

          <template v-else-if="field.fieldType === 'date'">
            <!-- Date list: multiple date inputs -->
            <span class="text-sm font-medium text-n-slate-12">{{
              field.key
            }}</span>
            <div class="grid gap-2">
              <div
                v-for="(value, index) in valuesByFieldId[field.id]"
                :key="index"
                class="flex items-center gap-2"
              >
                <NextInput
                  type="date"
                  :model-value="value"
                  @update:model-value="
                    newValue => {
                      valuesByFieldId[field.id][index] = newValue;
                    }
                  "
                />
                <Button
                  icon="i-lucide-x"
                  variant="ghost"
                  color="ruby"
                  size="sm"
                  :title="t('KANBAN.CARD_ADDITIONAL_DATA.REMOVE_VALUE')"
                  @click="removeDateValue(field, index)"
                />
              </div>
              <Button
                icon="i-lucide-plus"
                :label="t('KANBAN.CARD_ADDITIONAL_DATA.ADD_DATE')"
                color="slate"
                size="sm"
                class="w-fit"
                @click="addDateValue(field)"
              />
            </div>
          </template>

          <template v-else>
            <!-- Text / number list: tag-style input -->
            <NextInput
              :label="field.key"
              :type="field.fieldType === 'number' ? 'number' : 'text'"
              :model-value="tagDrafts[field.id]"
              :placeholder="t('KANBAN.CARD_ADDITIONAL_DATA.TAG_PLACEHOLDER')"
              @update:model-value="value => (tagDrafts[field.id] = value)"
              @enter="addTagValue(field)"
            />
            <div
              v-if="valuesByFieldId[field.id].length"
              class="flex flex-wrap gap-2"
            >
              <span
                v-for="(value, index) in valuesByFieldId[field.id]"
                :key="index"
                class="inline-flex items-center gap-2 rounded-full border border-n-weak bg-n-alpha-1 px-3 py-1 text-xs font-medium text-n-slate-11"
              >
                {{ value }}
                <button
                  type="button"
                  :aria-label="t('KANBAN.CARD_ADDITIONAL_DATA.REMOVE_VALUE')"
                  @click="removeTagValue(field, index)"
                >
                  <i class="i-lucide-x size-3" />
                </button>
              </span>
            </div>
          </template>
        </div>
      </div>
    </template>
  </div>
</template>
