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
      type: [Array, Object],
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
    kanbanStageSelection: {
      get() {
        const params = Array.isArray(this.action_params)
          ? this.action_params[0]
          : this.action_params;
        if (!params || !Array.isArray(this.dropdownValues)) return null;

        return (
          this.dropdownValues.find(
            option =>
              option.id ===
              `${params.kanban_board_id}:${params.kanban_stage_id}`
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
          {
            kanban_board_id: kanbanBoardId,
            kanban_stage_id: kanbanStageId,
          },
        ];
      },
    },
    kanbanBoardSelection: {
      get() {
        const params = Array.isArray(this.action_params)
          ? this.action_params[0]
          : this.action_params;
        const boards = this.dropdownValues?.boards || [];
        return (
          boards.find(board => board.id === params?.kanban_board_id) || null
        );
      },
      set(value) {
        if (!value) {
          this.action_params = [];
          return;
        }

        this.action_params = [{ kanban_board_id: value.id, agent_ids: [] }];
      },
    },
    kanbanAgentOptions() {
      const params = Array.isArray(this.action_params)
        ? this.action_params[0]
        : this.action_params;
      return (
        this.dropdownValues?.agentsByBoardId?.[params?.kanban_board_id] || []
      );
    },
    kanbanAgentSelections: {
      get() {
        const params = Array.isArray(this.action_params)
          ? this.action_params[0]
          : this.action_params;
        const agentIds = params?.agent_ids || [];
        return this.kanbanAgentOptions.filter(agent =>
          agentIds.includes(agent.id)
        );
      },
      set(value) {
        const params = Array.isArray(this.action_params)
          ? this.action_params[0]
          : this.action_params;
        if (!params?.kanban_board_id) return;

        this.action_params = [
          {
            kanban_board_id: params.kanban_board_id,
            agent_ids: (value || []).map(agent => agent.id),
          },
        ];
      },
    },
    kanbanStagePlaceholder() {
      if (this.isMacro) return this.$t('MACROS.KANBAN_STAGE_PLACEHOLDER');
      return this.$t('AUTOMATION.KANBAN_STAGE_PLACEHOLDER');
    },
    kanbanBoardPlaceholder() {
      if (this.isMacro) return this.$t('MACROS.KANBAN_BOARD_PLACEHOLDER');
      return this.$t('AUTOMATION.KANBAN_BOARD_PLACEHOLDER');
    },
    kanbanAgentPlaceholder() {
      if (this.isMacro) return this.$t('MACROS.KANBAN_AGENT_PLACEHOLDER');
      return this.$t('AUTOMATION.KANBAN_AGENT_PLACEHOLDER');
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
            :placeholder="kanbanStagePlaceholder"
            :dropdown-max-height="dropdownMaxHeight"
          />
          <div
            v-else-if="inputType === 'kanban_agents'"
            class="flex flex-wrap items-center gap-2"
          >
            <SingleSelect
              v-model="kanbanBoardSelection"
              :options="dropdownValues.boards || []"
              :placeholder="kanbanBoardPlaceholder"
              :dropdown-max-height="dropdownMaxHeight"
            />
            <MultiSelect
              v-model="kanbanAgentSelections"
              :options="kanbanAgentOptions"
              :placeholder="kanbanAgentPlaceholder"
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
