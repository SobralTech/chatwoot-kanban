import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters } from 'dashboard/composables/store';
import { PRIORITY_CONDITION_VALUES } from 'dashboard/constants/automation';
import {
  KANBAN_AGENT_ACTIONS,
  KANBAN_STAGE_ACTIONS,
  getKanbanAgentOptionsByBoard,
  getKanbanBoardOptions,
  getKanbanStageOptions,
} from 'dashboard/helper/kanbanActionOptions';

/**
 * Composable for handling macro-related functionality
 * @returns {Object} An object containing the getMacroDropdownValues function
 */
export const useMacros = () => {
  const { t } = useI18n();
  const getters = useStoreGetters();

  const labels = computed(() => getters['labels/getLabels'].value);
  const teams = computed(() => getters['teams/getTeams'].value);
  const agents = computed(() => getters['agents/getVerifiedAgents'].value);
  const kanbanBoards = computed(
    () => getters['kanbanBoards/kanbanBoards']?.value || []
  );

  const withNoneOption = options => [
    { id: 'nil', name: t('AUTOMATION.NONE_OPTION') },
    ...(options || []),
  ];

  /**
   * Get dropdown values based on the specified type
   * @param {string} type - The type of dropdown values to retrieve
   * @returns {Array} An array of dropdown values
   */
  const getMacroDropdownValues = type => {
    if (KANBAN_STAGE_ACTIONS.includes(type)) {
      return getKanbanStageOptions(kanbanBoards.value, type);
    }

    if (KANBAN_AGENT_ACTIONS.includes(type)) {
      return {
        boards: getKanbanBoardOptions(kanbanBoards.value),
        agentsByBoardId: getKanbanAgentOptionsByBoard(
          kanbanBoards.value,
          agents.value
        ),
      };
    }

    switch (type) {
      case 'assign_team':
        return withNoneOption(teams.value);
      case 'send_email_to_team':
        return teams.value;
      case 'assign_agent':
        return [
          ...withNoneOption(),
          { id: 'self', name: 'Self' },
          ...agents.value,
        ];
      case 'add_label':
      case 'remove_label':
        return labels.value.map(i => ({
          id: i.title,
          name: i.title,
        }));
      case 'change_priority':
        return PRIORITY_CONDITION_VALUES.map(item => ({
          id: item.id,
          name: t(`MACROS.PRIORITY_TYPES.${item.i18nKey}`),
        }));
      default:
        return [];
    }
  };

  return {
    getMacroDropdownValues,
  };
};
