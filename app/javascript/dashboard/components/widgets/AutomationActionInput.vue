<script>
import AutomationActionTeamMessageInput from './AutomationActionTeamMessageInput.vue';
import AutomationActionFileInput from './AutomationFileInput.vue';
import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import MultiSelect from 'dashboard/components-next/filter/inputs/MultiSelect.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import { parseBoardStageId } from 'dashboard/helper/kanbanActionOptions';

export default {
  components: {
    AutomationActionTeamMessageInput,
    AutomationActionFileInput,
    WootMessageEditor,
    NextButton,
    SingleSelect,
    MultiSelect,
    NextInput,
  },
  props: {
    modelValue: {
      type: Object,
      default: () => null,
    },
    actionTypes: {
      type: Array,
      default: () => [],
    },
    dropdownValues: {
      type: Array,
      default: () => [],
    },
    errorMessage: {
      type: String,
      default: '',
    },
    showActionInput: {
      type: Boolean,
      default: true,
    },
    initialFileName: {
      type: String,
      default: '',
    },
    isMacro: {
      type: Boolean,
      default: false,
    },
    dropdownMaxHeight: {
      type: String,
      default: 'max-h-80',
    },
  },
  emits: ['update:modelValue', 'input', 'removeAction', 'resetAction'],
  computed: {
    action_name: {
      get() {
        if (!this.modelValue) return null;
        return this.modelValue.action_name;
      },
      set(value) {
        const payload = this.modelValue || {};
        this.$emit('update:modelValue', { ...payload, action_name: value });
        this.$emit('input', { ...payload, action_name: value });
      },
    },
    action_params: {
      get() {
        if (!this.modelValue) return null;
        return this.modelValue.action_params;
      },
      set(value) {
        const payload = this.modelValue || {};
        this.$emit('update:modelValue', { ...payload, action_params: value });
        this.$emit('input', { ...payload, action_params: value });
      },
    },
    inputType() {
      return this.actionTypes.find(action => action.key === this.action_name)
        ?.inputType;
    },
    actionNameAsSelectModel: {
      get() {
        if (!this.action_name) return null;
        const found = this.actionTypes.find(a => a.key === this.action_name);
        return found ? { id: found.key, name: found.label } : null;
      },
      set(value) {
        this.action_name = value?.id || value;
      },
    },
    actionTypesAsOptions() {
      return this.actionTypes.map(a => ({ id: a.key, name: a.label }));
    },
    // Automation and macro action_params are a one-element array around the hash.
    kanbanParams() {
      return (
        (Array.isArray(this.action_params)
          ? this.action_params[0]
          : this.action_params) || {}
      );
    },
    kanbanStageSelection: {
      get() {
        const { kanban_board_id: boardId, kanban_stage_id: stageId } =
          this.kanbanParams;
        return (
          this.dropdownValues.find(
            option => option.id === `${boardId}:${stageId}`
          ) || null
        );
      },
      set(value) {
        if (!value) {
          this.action_params = [];
          return;
        }

        const { kanbanBoardId, kanbanStageId } = parseBoardStageId(value.id);
        this.action_params = [
          { kanban_board_id: kanbanBoardId, kanban_stage_id: kanbanStageId },
        ];
      },
    },
    kanbanBoardSelection: {
      get() {
        return (
          this.dropdownValues.find(
            board => board.id === this.kanbanParams.kanban_board_id
          ) || null
        );
      },
      set(value) {
        this.action_params = value
          ? [{ kanban_board_id: value.id, agent_ids: [] }]
          : [];
      },
    },
    kanbanAgentOptions() {
      return this.kanbanBoardSelection?.agents || [];
    },
    kanbanAgentSelections: {
      get() {
        const agentIds = this.kanbanParams.agent_ids || [];
        return this.kanbanAgentOptions.filter(agent =>
          agentIds.includes(agent.id)
        );
      },
      set(value) {
        const boardId = this.kanbanParams.kanban_board_id;
        if (!boardId) return;

        this.action_params = [
          {
            kanban_board_id: boardId,
            agent_ids: (value || []).map(agent => agent.id),
          },
        ];
      },
    },
    kanbanPlaceholders() {
      if (this.isMacro) {
        return {
          stage: this.$t('MACROS.KANBAN_STAGE_PLACEHOLDER'),
          board: this.$t('MACROS.KANBAN_BOARD_PLACEHOLDER'),
          agent: this.$t('MACROS.KANBAN_AGENT_PLACEHOLDER'),
        };
      }
      return {
        stage: this.$t('AUTOMATION.KANBAN_STAGE_PLACEHOLDER'),
        board: this.$t('AUTOMATION.KANBAN_BOARD_PLACEHOLDER'),
        agent: this.$t('AUTOMATION.KANBAN_AGENT_PLACEHOLDER'),
      };
    },
    isVerticalLayout() {
      return ['team_message', 'textarea'].includes(this.inputType);
    },
    castMessageVmodel: {
      get() {
        if (Array.isArray(this.action_params)) {
          return this.action_params[0];
        }
        return this.action_params;
      },
      set(value) {
        this.action_params = value;
      },
    },
  },
  methods: {
    removeAction() {
      this.$emit('removeAction');
    },
    resetAction() {
      this.$emit('resetAction');
    },
    onActionNameChange(value) {
      this.actionNameAsSelectModel = value;
      this.resetAction();
    },
  },
};
</script>

<template>
  <li class="list-none py-2 first:pt-0 last:pb-0">
    <div
      class="flex flex-col gap-2"
      :class="{ 'animate-wiggle': errorMessage }"
    >
      <div class="flex items-center gap-2">
        <SingleSelect
          :model-value="actionNameAsSelectModel"
          :options="actionTypesAsOptions"
          :dropdown-max-height="dropdownMaxHeight"
          disable-deselect
          class="flex-shrink-0"
          @update:model-value="onActionNameChange"
        />
        <template v-if="showActionInput && !isVerticalLayout">
          <SingleSelect
            v-if="inputType === 'kanban_stage'"
            v-model="kanbanStageSelection"
            :options="dropdownValues"
            :placeholder="kanbanPlaceholders.stage"
            :dropdown-max-height="dropdownMaxHeight"
          />
          <div
            v-else-if="inputType === 'kanban_agents'"
            class="flex flex-wrap items-center gap-2"
          >
            <SingleSelect
              v-model="kanbanBoardSelection"
              :options="dropdownValues"
              :placeholder="kanbanPlaceholders.board"
              :dropdown-max-height="dropdownMaxHeight"
            />
            <MultiSelect
              v-model="kanbanAgentSelections"
              :options="kanbanAgentOptions"
              :placeholder="kanbanPlaceholders.agent"
              :dropdown-max-height="dropdownMaxHeight"
            />
          </div>
          <SingleSelect
            v-else-if="inputType === 'search_select'"
            v-model="action_params"
            :options="dropdownValues"
            :dropdown-max-height="dropdownMaxHeight"
          />
          <MultiSelect
            v-else-if="inputType === 'multi_select'"
            v-model="action_params"
            :options="dropdownValues"
            :dropdown-max-height="dropdownMaxHeight"
          />
          <NextInput
            v-else-if="inputType === 'email'"
            v-model="action_params"
            type="email"
            size="sm"
            :placeholder="$t('AUTOMATION.ACTION.EMAIL_INPUT_PLACEHOLDER')"
          />
          <NextInput
            v-else-if="inputType === 'url'"
            v-model="action_params"
            type="url"
            size="sm"
            :placeholder="$t('AUTOMATION.ACTION.URL_INPUT_PLACEHOLDER')"
          />
          <AutomationActionFileInput
            v-else-if="inputType === 'attachment'"
            v-model="action_params"
            :initial-file-name="initialFileName"
          />
        </template>
        <NextButton
          v-if="!isMacro"
          sm
          solid
          slate
          icon="i-lucide-trash"
          class="flex-shrink-0"
          @click="removeAction"
        />
      </div>
      <AutomationActionTeamMessageInput
        v-if="inputType === 'team_message'"
        v-model="action_params"
        :teams="dropdownValues"
        :dropdown-max-height="dropdownMaxHeight"
      />
      <WootMessageEditor
        v-if="inputType === 'textarea'"
        v-model="castMessageVmodel"
        rows="4"
        enable-variables
        :placeholder="$t('AUTOMATION.ACTION.TEAM_MESSAGE_INPUT_PLACEHOLDER')"
        class="[&_.ProseMirror-menubar]:hidden px-3 py-1 bg-n-alpha-1 rounded-lg outline outline-1 outline-n-weak dark:outline-n-strong"
      />
    </div>
    <span v-if="errorMessage" class="text-sm text-n-ruby-11">
      {{ errorMessage }}
    </span>
  </li>
</template>
