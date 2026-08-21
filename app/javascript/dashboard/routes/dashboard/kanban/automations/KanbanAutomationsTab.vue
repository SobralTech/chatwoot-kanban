<script setup>
import { computed, onMounted, ref, toRaw, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';
import Draggable from 'vuedraggable';

import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import KanbanAutomationLogList from './KanbanAutomationLogList.vue';
import KanbanAutomationRuleForm from './KanbanAutomationRuleForm.vue';
import KanbanAutomationRuleRow from './KanbanAutomationRuleRow.vue';

const props = defineProps({
  boardId: {
    type: [Number, String],
    required: true,
  },
  stages: {
    type: Array,
    default: () => [],
  },
  automationSettings: {
    type: Object,
    default: () => ({}),
  },
  initialView: {
    type: String,
    default: 'rules',
    validator: value => ['rules', 'log'].includes(value),
  },
  initialRuleId: {
    type: [Number, String],
    default: null,
  },
});

const { t } = useI18n();
const store = useStore();
const agents = useMapGetter('agents/getAgents');
const labels = useMapGetter('labels/getLabels');
const inboxes = useMapGetter('inboxes/getAllInboxes');

const rules = ref([]);
const reasons = ref([]);
const isLoading = ref(false);
const loadError = ref('');
const isSaving = ref(false);
const isToggling = ref(false);
const activeView = ref(props.initialView);
const initialRuleId = Number(props.initialRuleId);
const selectedRuleId = ref(
  Number.isInteger(initialRuleId) && initialRuleId > 0
    ? initialRuleId
    : props.initialRuleId
);
const draftRule = ref(null);
const formMode = ref('create');
const hasSimulatedLog = ref(false);
const showDeleteConfirmation = ref(false);
const rulePendingDeletion = ref(null);
const automationEnabled = ref(props.automationSettings?.enabled ?? true);

const formRef = ref(null);

const tabItems = computed(() => [
  { value: 'rules', label: t('KANBAN.AUTOMATIONS.TABS.RULES') },
  { value: 'log', label: t('KANBAN.AUTOMATIONS.TABS.LOG') },
]);

const activeTabIndex = computed(() =>
  tabItems.value.findIndex(tab => tab.value === activeView.value)
);

const regularStages = computed(() =>
  props.stages.filter(stage => !stage.special && !stage.isTerminal)
);

const getErrorMessage = (error, fallback) =>
  error?.response?.data?.error ||
  error?.response?.data?.message ||
  error?.message ||
  fallback;

const defaultRule = () => ({
  name: '',
  description: '',
  event_name: 'card_created',
  position: rules.value.length + 1,
  conditions: [
    {
      attribute_key: 'stage_id',
      filter_operator: 'equal_to',
      values: [],
    },
  ],
  actions: [
    {
      action_name: 'move_to_stage',
      action_params: { stage_id: regularStages.value[0]?.id || '' },
    },
  ],
  dry_run: true,
  active: false,
  stop_after_match: false,
});

// A rule is a document whose keys are the API contract -- event_name, attribute_key,
// action_params -- and the form edits it as it arrives, the way the conversation
// automation form does. Only the resources around it (agents, reasons) are camelised.
const formRule = source => structuredClone(toRaw(source));

const fetchRules = async () => {
  isLoading.value = true;
  loadError.value = '';

  try {
    const response = await KanbanBoardsAPI.getAutomationRules(props.boardId);
    rules.value = response.data?.payload || [];
  } catch (error) {
    loadError.value = getErrorMessage(
      error,
      t('KANBAN.AUTOMATIONS.LOAD_ERROR')
    );
  } finally {
    isLoading.value = false;
  }
};

const fetchReasons = async () => {
  try {
    const response = await KanbanBoardsAPI.getReasons(props.boardId);
    reasons.value = camelcaseKeys(response.data || [], { deep: true });
  } catch {
    reasons.value = [];
  }
};

const loadSimulatedLog = async ruleId => {
  if (!ruleId) {
    hasSimulatedLog.value = false;
    return;
  }

  try {
    const response = await KanbanBoardsAPI.getAutomationLogs(props.boardId, {
      rule_id: ruleId,
      status: 'simulated',
      limit: 1,
    });
    hasSimulatedLog.value = Boolean(response.data?.payload?.length);
  } catch {
    hasSimulatedLog.value = false;
  }
};

const openCreate = () => {
  formMode.value = 'create';
  selectedRuleId.value = null;
  hasSimulatedLog.value = false;
  draftRule.value = defaultRule();
  formRef.value?.open();
};

const openEdit = async rule => {
  formMode.value = 'edit';
  selectedRuleId.value = rule.id;
  draftRule.value = formRule(rule);
  await loadSimulatedLog(rule.id);
  formRef.value?.open();
};

const duplicateRule = rule => {
  formMode.value = 'create';
  selectedRuleId.value = null;
  hasSimulatedLog.value = false;
  const sourceRule = formRule(rule);
  draftRule.value = {
    ...sourceRule,
    id: undefined,
    name: `${rule.name} ${t('KANBAN.AUTOMATIONS.DUPLICATE_SUFFIX')}`,
    position: rules.value.length + 1,
    active: false,
    dry_run: true,
  };
  formRef.value?.open();
};

const previewRule = async payload => {
  const response = await KanbanBoardsAPI.previewAutomationRule(props.boardId, {
    automation_rule: payload,
  });
  return response.data;
};

const saveRule = async payload => {
  if (isSaving.value) return;

  isSaving.value = true;
  try {
    const request = { automation_rule: payload };
    const shouldActivate =
      formMode.value === 'edit' &&
      payload.dry_run === false &&
      !draftRule.value?.active;
    if (formMode.value === 'edit' && draftRule.value?.id) {
      await KanbanBoardsAPI.updateAutomationRule(
        props.boardId,
        draftRule.value.id,
        request
      );
      if (shouldActivate) {
        await KanbanBoardsAPI.toggleAutomationRule(
          props.boardId,
          draftRule.value.id,
          true
        );
      }
    } else {
      await KanbanBoardsAPI.createAutomationRule(props.boardId, request);
    }
    formRef.value?.close();
    await fetchRules();
    useAlert(
      formMode.value === 'edit'
        ? t('KANBAN.AUTOMATIONS.SAVED')
        : t('KANBAN.AUTOMATIONS.CREATED')
    );
  } catch (error) {
    useAlert(getErrorMessage(error, t('KANBAN.AUTOMATIONS.SAVE_ERROR')));
  } finally {
    isSaving.value = false;
  }
};

const toggleRule = async rule => {
  if (isToggling.value) return;

  isToggling.value = true;
  try {
    await KanbanBoardsAPI.toggleAutomationRule(
      props.boardId,
      rule.id,
      !rule.active
    );
    await fetchRules();
  } catch (error) {
    useAlert(getErrorMessage(error, t('KANBAN.AUTOMATIONS.TOGGLE_ERROR')));
  } finally {
    isToggling.value = false;
  }
};

const requestDelete = rule => {
  rulePendingDeletion.value = rule;
  showDeleteConfirmation.value = true;
};

const closeDeleteConfirmation = () => {
  showDeleteConfirmation.value = false;
  rulePendingDeletion.value = null;
};

const deleteRule = async () => {
  const rule = rulePendingDeletion.value;
  if (!rule) return;

  try {
    await KanbanBoardsAPI.deleteAutomationRule(props.boardId, rule.id);
    closeDeleteConfirmation();
    await fetchRules();
    useAlert(t('KANBAN.AUTOMATIONS.DELETED'));
  } catch (error) {
    useAlert(getErrorMessage(error, t('KANBAN.AUTOMATIONS.DELETE_ERROR')));
  }
};

const openLog = rule => {
  selectedRuleId.value = rule.id;
  activeView.value = 'log';
};

const onTabChanged = tab => {
  activeView.value = tab.value;
  if (tab.value === 'log') selectedRuleId.value = null;
};

const onRuleDragEnd = async event => {
  const oldIndex = event?.oldIndex;
  const newIndex = event?.newIndex;
  if (
    oldIndex === undefined ||
    newIndex === undefined ||
    oldIndex === newIndex
  ) {
    return;
  }

  if (!rules.value[newIndex]?.id) return;

  try {
    await KanbanBoardsAPI.reorderAutomationRules(
      props.boardId,
      rules.value.map(orderedRule => orderedRule.id)
    );
    await fetchRules();
  } catch (error) {
    useAlert(getErrorMessage(error, t('KANBAN.AUTOMATIONS.REORDER_ERROR')));
    await fetchRules();
  }
};

const toggleKillSwitch = async previousValue => {
  if (isToggling.value) {
    automationEnabled.value = previousValue;
    return;
  }

  const checked = automationEnabled.value;
  const previous =
    typeof previousValue === 'boolean' ? previousValue : !checked;
  isToggling.value = true;
  try {
    await KanbanBoardsAPI.updateSettings(props.boardId, {
      kanban_board: {
        automation_settings: {
          ...props.automationSettings,
          enabled: checked,
        },
      },
    });
  } catch (error) {
    automationEnabled.value = previous;
    useAlert(getErrorMessage(error, t('KANBAN.AUTOMATIONS.KILL_SWITCH_ERROR')));
  } finally {
    isToggling.value = false;
  }
};

watch(
  () => props.automationSettings,
  settings => {
    if (settings && 'enabled' in settings) {
      automationEnabled.value = settings.enabled;
    }
  },
  { deep: true }
);

onMounted(async () => {
  await Promise.all([
    fetchRules(),
    fetchReasons(),
    store.dispatch('agents/get'),
    store.dispatch('labels/get'),
    store.dispatch('inboxes/get'),
  ]);
});
</script>

<template>
  <section
    class="mx-auto grid w-full max-w-4xl gap-4 p-6"
    data-testid="kanban-automations-tab"
  >
    <p class="text-xs text-n-slate-10">
      {{ t('KANBAN.BOARD_EDIT.AUTOSAVE_NOTE') }}
    </p>

    <section
      class="flex flex-wrap items-center justify-between gap-4 rounded-lg border border-n-brand/30 bg-n-blue-2 p-4"
    >
      <div class="min-w-0">
        <h2 class="mb-1 text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.AUTOMATIONS.KILL_SWITCH') }}
        </h2>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('KANBAN.AUTOMATIONS.KILL_SWITCH_HELP') }}
        </p>
      </div>
      <Switch
        v-model="automationEnabled"
        data-testid="kanban-automations-kill-switch"
        @change="toggleKillSwitch"
      />
    </section>

    <div class="flex flex-wrap items-center justify-between gap-3">
      <TabBar
        :tabs="tabItems"
        :initial-active-tab="activeTabIndex"
        @tab-changed="onTabChanged"
      />
      <Button
        v-if="activeView === 'rules'"
        icon="i-lucide-plus"
        :label="t('KANBAN.AUTOMATIONS.ADD_RULE')"
        color="blue"
        size="sm"
        data-testid="kanban-automations-add-rule"
        @click="openCreate"
      />
    </div>

    <p v-if="isLoading" class="py-8 text-center text-sm text-n-slate-11">
      {{ t('KANBAN.AUTOMATIONS.LOADING') }}
    </p>
    <p
      v-else-if="loadError"
      class="rounded-md bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
    >
      {{ loadError }}
    </p>

    <template v-else-if="activeView === 'rules'">
      <div
        v-if="rules.length === 0"
        class="grid justify-items-center gap-2 rounded-lg border border-dashed border-n-weak px-6 py-12 text-center"
      >
        <i class="i-lucide-zap size-7 text-n-slate-10" />
        <h2 class="mb-0 text-base font-medium text-n-slate-12">
          {{ t('KANBAN.AUTOMATIONS.EMPTY_TITLE') }}
        </h2>
        <p class="mb-2 max-w-md text-sm text-n-slate-11">
          {{ t('KANBAN.AUTOMATIONS.EMPTY_DESCRIPTION') }}
        </p>
        <Button
          icon="i-lucide-plus"
          :label="t('KANBAN.AUTOMATIONS.ADD_RULE')"
          color="blue"
          size="sm"
          @click="openCreate"
        />
      </div>

      <Draggable
        v-else
        v-model="rules"
        item-key="id"
        handle=".automation-drag-handle"
        ghost-class="opacity-60"
        chosen-class="opacity-90"
        class="grid gap-2"
        :animation="180"
        @end="onRuleDragEnd"
      >
        <template #item="{ element }">
          <KanbanAutomationRuleRow
            :rule="element"
            :stages="regularStages"
            :automations-enabled="automationEnabled"
            @edit="openEdit"
            @duplicate="duplicateRule"
            @log="openLog"
            @toggle="toggleRule"
            @delete="requestDelete"
          />
        </template>
      </Draggable>
    </template>

    <KanbanAutomationLogList
      v-else
      :board-id="boardId"
      :rules="rules"
      :selected-rule-id="selectedRuleId"
    />

    <KanbanAutomationRuleForm
      ref="formRef"
      v-model:rule="draftRule"
      :mode="formMode"
      :stages="regularStages"
      :agents="agents"
      :labels="labels"
      :inboxes="inboxes"
      :reasons="reasons"
      :has-simulated-log="hasSimulatedLog"
      :is-saving="isSaving"
      :preview-rule="previewRule"
      @save="saveRule"
    />

    <woot-delete-modal
      v-model:show="showDeleteConfirmation"
      :on-close="closeDeleteConfirmation"
      :on-confirm="deleteRule"
      :title="t('KANBAN.AUTOMATIONS.DELETE.TITLE')"
      :message="t('KANBAN.AUTOMATIONS.DELETE.MESSAGE')"
      :confirm-text="t('KANBAN.AUTOMATIONS.DELETE.CONFIRM')"
      :reject-text="t('KANBAN.AUTOMATIONS.DELETE.CANCEL')"
    />
  </section>
</template>
