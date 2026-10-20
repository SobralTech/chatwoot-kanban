<script setup>
import { computed, ref, watch } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';
import { useTimeoutFn } from '@vueuse/core';
import { useAlert, useTrack } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAgentsList } from 'dashboard/composables/useAgentsList';
import { useConversationLabels } from 'dashboard/composables/useConversationLabels';
import { useConversationSuggestions } from 'dashboard/composables/useConversationSuggestions';
import { CONVERSATION_PRIORITY } from 'shared/constants/messages';
import {
  CAPTAIN_EVENTS,
  CONVERSATION_EVENTS,
} from 'dashboard/helper/AnalyticsHelper/events';
import Avatar from 'next/avatar/Avatar.vue';
import ContactDetailsItem from './ContactDetailsItem.vue';
import ConversationApi from 'dashboard/api/inbox/conversation';
import MultiselectDropdown from 'shared/components/ui/MultiselectDropdown.vue';
import ConversationLabels from './labels/LabelBox.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import SuggestButton from 'dashboard/components-next/captain/classifier/SuggestButton.vue';
import SuggestionSkeleton from 'dashboard/components-next/captain/classifier/SuggestionSkeleton.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const EMPTY_NOTE_DURATION = 2500;

const store = useStore();
const { t } = useI18n();

const currentChat = useMapGetter('getSelectedChat');
const currentUser = useMapGetter('getCurrentUser');
const teams = useMapGetter('teams/getTeams');

const { agentsList } = useAgentsList(true, { includeAIAssignees: true });
const { isAdmin } = useAdmin();
const { accountLabels, savedLabels, onUpdateLabels } = useConversationLabels();

const {
  isEnabled: isSuggestionsEnabled,
  isActive: isPrioritySuggestionActive,
  isLoading: isSuggestingPriority,
  suggestions: prioritySuggestion,
  toggleSuggestions: togglePrioritySuggestion,
  dismiss: dismissPrioritySuggestion,
} = useConversationSuggestions('priority', currentChat);

const {
  isActive: isLabelSuggestionActive,
  isLoading: isSuggestingLabels,
  suggestions: labelSuggestion,
  toggleSuggestions: toggleLabelSuggestions,
  dismiss: dismissLabelSuggestions,
} = useConversationSuggestions('labels', currentChat);

const priorityOptions = computed(() => [
  {
    id: null,
    name: t('CONVERSATION.PRIORITY.OPTIONS.NONE'),
    icon: 'i-woot-priority-empty',
  },
  {
    id: CONVERSATION_PRIORITY.URGENT,
    name: t('CONVERSATION.PRIORITY.OPTIONS.URGENT'),
    icon: 'i-woot-priority-urgent',
  },
  {
    id: CONVERSATION_PRIORITY.HIGH,
    name: t('CONVERSATION.PRIORITY.OPTIONS.HIGH'),
    icon: 'i-woot-priority-high',
  },
  {
    id: CONVERSATION_PRIORITY.MEDIUM,
    name: t('CONVERSATION.PRIORITY.OPTIONS.MEDIUM'),
    icon: 'i-woot-priority-medium',
  },
  {
    id: CONVERSATION_PRIORITY.LOW,
    name: t('CONVERSATION.PRIORITY.OPTIONS.LOW'),
    icon: 'i-woot-priority-low',
  },
]);

const teamsList = computed(() => {
  if (currentChat.value?.meta?.team) {
    return [{ id: 0, name: t('TEAMS_SETTINGS.LIST.NONE') }, ...teams.value];
  }
  return teams.value;
});

const assignedAgent = computed({
  get() {
    const assignee = currentChat.value.meta.assignee;
    return (
      assignee && {
        ...assignee,
        assignee_type: currentChat.value.meta.assignee_type || 'User',
      }
    );
  },
  set(agent) {
    const agentId = agent ? agent.id : null;
    const assigneeType = agent ? agent.assignee_type || 'User' : null;
    store.dispatch('setCurrentChatAssignee', {
      conversationId: currentChat.value.id,
      assignee: agent,
      assigneeType,
    });
    store
      .dispatch('assignAgent', {
        conversationId: currentChat.value.id,
        agentId,
        assigneeType,
      })
      .then(() => {
        useAlert(t('CONVERSATION.CHANGE_AGENT'));
      });
  },
});

const assignedTeam = computed({
  get() {
    return currentChat.value.meta.team;
  },
  set(team) {
    const conversationId = currentChat.value.id;
    const teamId = team ? team.id : 0;
    store.dispatch('setCurrentChatTeam', { team, conversationId });
    store.dispatch('assignTeam', { conversationId, teamId }).then(() => {
      useAlert(t('CONVERSATION.CHANGE_TEAM'));
    });
  },
});

const assignedPriority = computed({
  get() {
    const selectedOption = priorityOptions.value.find(
      opt => opt.id === currentChat.value.priority
    );
    return selectedOption || priorityOptions.value[0];
  },
  set(priorityItem) {
    const conversationId = currentChat.value.id;
    const oldValue = currentChat.value?.priority;
    const priority = priorityItem.id;

    store.dispatch('setCurrentChatPriority', { priority, conversationId });
    store.dispatch('assignPriority', { conversationId, priority }).then(() => {
      useTrack(CONVERSATION_EVENTS.CHANGE_PRIORITY, {
        oldValue,
        newValue: priority,
        from: 'Conversation Sidebar',
      });
      useAlert(
        t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.SUCCESSFUL', {
          priority: priorityItem.name,
          conversationId,
        })
      );
    });
  },
});

const showSelfAssign = computed(() => {
  if (!assignedAgent.value) return true;
  return (
    assignedAgent.value.id !== currentUser.value.id ||
    (assignedAgent.value.assignee_type || 'User') !== 'User'
  );
});

const suggestedPriority = computed(() => {
  const priority = prioritySuggestion.value?.priority;
  if (priority === currentChat.value.priority) return undefined;
  return priorityOptions.value.find(opt => opt.id === priority);
});

const rejectedLabels = ref([]);

const suggestedLabels = computed(() => {
  const titles = (labelSuggestion.value?.labels || []).map(
    ({ title }) => title
  );
  return accountLabels.value.filter(
    ({ title }) =>
      titles.includes(title) &&
      !savedLabels.value.includes(title) &&
      !rejectedLabels.value.includes(title)
  );
});

const { start: hideEmptyNote, stop: cancelHideEmptyNote } = useTimeoutFn(
  dismissLabelSuggestions,
  EMPTY_NOTE_DURATION,
  { immediate: false }
);

// Nothing left to show: close right away when the user handled every
// suggestion, or after a short "no new suggestions" note otherwise.
watch(
  () => [
    isLabelSuggestionActive.value,
    isSuggestingLabels.value,
    suggestedLabels.value.length,
  ],
  ([isActive, isLoading, remaining], [, , previous]) => {
    cancelHideEmptyNote();
    if (!isActive || isLoading || remaining) return;

    if (previous) dismissLabelSuggestions();
    else hideEmptyNote();
  }
);

const accessUsers = ref([]);
const eligibleAccessUsers = ref([]);
const accessMode = ref('all_agents');
const accessSearchQuery = ref('');
const isAccessDropdownOpen = ref(false);
const isAccessLoading = ref(false);
const isAccessSaving = ref(false);

const accessUsersById = computed(
  () => new Map(eligibleAccessUsers.value.map(user => [user.id, user]))
);
const selectedAccessUsers = computed(() =>
  accessUsers.value.map(user => {
    const eligibleUser = accessUsersById.value.get(user.id);
    return { ...(eligibleUser || {}), ...user, isRevoked: !eligibleUser };
  })
);
const selectedAccessUserIds = computed(() =>
  selectedAccessUsers.value.map(user => user.id)
);
const hasRevokedAccessUsers = computed(() =>
  selectedAccessUsers.value.some(user => user.isRevoked)
);
const isAdminsOnly = computed(() => accessMode.value === 'admins_only');
const accessSummaryLabel = computed(() => {
  if (isAdminsOnly.value) return t('CONVERSATION.ACCESS_CONTROL.ADMINS_ONLY');
  if (!selectedAccessUsers.value.length) {
    return t('CONVERSATION.ACCESS_CONTROL.ALL_AGENTS');
  }

  const names = selectedAccessUsers.value.map(user => user.name);
  if (names.length <= 2) return names.join(', ');
  return `${names.slice(0, 2).join(', ')}...`;
});
const filteredEligibleAccessUsers = computed(() => {
  const searchQuery = accessSearchQuery.value.trim().toLowerCase();
  return eligibleAccessUsers.value.filter(
    user =>
      selectedAccessUserIds.value.includes(user.id) ||
      !searchQuery ||
      user.name.toLowerCase().includes(searchQuery)
  );
});

const normalizeAccessUsers = (users = []) =>
  [...new Map(users.map(user => [user.id, user])).values()]
    .filter(user => user && user.id)
    .map(user => ({
      id: user.id,
      name: user.name || user.available_name || '',
      thumbnail: user.thumbnail || user.avatar_url || '',
      availability_status: user.availability_status,
    }));

const extractUsers = response => {
  const payload =
    response?.data?.payload || response?.data?.data || response?.data || [];
  return Array.isArray(payload)
    ? payload
    : payload?.users || payload?.records || [];
};

const fetchAccessUsers = async () => {
  if (!isAdmin.value) return;

  isAccessLoading.value = true;
  try {
    const [selectedResponse, eligibleResponse] = await Promise.all([
      ConversationApi.getAccessUsers(props.conversationId),
      ConversationApi.getEligibleAccessUsers(props.conversationId),
    ]);
    accessUsers.value = normalizeAccessUsers(extractUsers(selectedResponse));
    eligibleAccessUsers.value = normalizeAccessUsers(
      extractUsers(eligibleResponse)
    );
    accessMode.value = selectedResponse?.data?.access_mode || 'all_agents';
  } finally {
    isAccessLoading.value = false;
  }
};

watch(() => props.conversationId, fetchAccessUsers, { immediate: true });

const closeAccessDropdown = () => {
  isAccessDropdownOpen.value = false;
  accessSearchQuery.value = '';
};

const toggleAccessDropdown = () => {
  if (isAccessDropdownOpen.value) {
    closeAccessDropdown();
    return;
  }
  isAccessDropdownOpen.value = true;
  accessSearchQuery.value = '';
};

const persistAccessUsers = async (nextUsers, mode = accessMode.value) => {
  isAccessSaving.value = true;
  accessUsers.value = nextUsers;
  accessMode.value = mode;
  try {
    await ConversationApi.updateAccessUsers({
      conversationId: props.conversationId,
      userIds: nextUsers.map(user => user.id),
      accessMode: mode,
    });
    await fetchAccessUsers();
  } finally {
    isAccessSaving.value = false;
  }
};

const setAccessMode = async mode => {
  if (accessMode.value === mode) return;
  const nextUsers = mode === 'selected_agents' ? accessUsers.value : [];
  await persistAccessUsers(nextUsers, mode);
};

const onToggleAccessUser = async user => {
  const isSelected = selectedAccessUserIds.value.includes(user.id);
  const nextUsers = isSelected
    ? accessUsers.value.filter(selectedUser => selectedUser.id !== user.id)
    : [...accessUsers.value, user];
  await persistAccessUsers(nextUsers, 'selected_agents');
};

const accessChipTitle = user =>
  user.isRevoked
    ? t('CONVERSATION.ACCESS_CONTROL.REVOKED_AGENT_TITLE', { name: user.name })
    : user.name;

const onSelfAssign = () => {
  const {
    account_id,
    availability_status,
    available_name,
    email,
    id,
    name,
    role,
    avatar_url,
  } = currentUser.value;
  assignedAgent.value = {
    account_id,
    availability_status,
    available_name,
    email,
    id,
    name,
    role,
    thumbnail: avatar_url,
  };
};

const onClickAssignAgent = selectedItem => {
  const isSameAgent =
    assignedAgent.value?.id === selectedItem.id &&
    (assignedAgent.value?.assignee_type || 'User') ===
      (selectedItem.assignee_type || 'User');
  assignedAgent.value = isSameAgent ? null : selectedItem;
};

const onClickAssignTeam = selectedItemTeam => {
  const isSameTeam = assignedTeam.value?.id === selectedItemTeam.id;
  assignedTeam.value = isSameTeam ? null : selectedItemTeam;
};

const onClickAssignPriority = selectedPriorityItem => {
  const isSamePriority = assignedPriority.value?.id === selectedPriorityItem.id;
  assignedPriority.value = isSamePriority
    ? priorityOptions.value[0]
    : selectedPriorityItem;
};

const acceptSuggestedPriority = () => {
  assignedPriority.value = suggestedPriority.value;
  dismissPrioritySuggestion();
};

const suggestPriority = () => {
  if (!isPrioritySuggestionActive.value) {
    useTrack(CAPTAIN_EVENTS.PRIORITY_SUGGESTION_REQUESTED, {
      conversationId: currentChat.value.id,
    });
  }
  togglePrioritySuggestion();
};

const suggestLabels = () => {
  if (!isLabelSuggestionActive.value) {
    useTrack(CAPTAIN_EVENTS.LABEL_SUGGESTIONS_REQUESTED, {
      conversationId: currentChat.value.id,
    });
  }
  rejectedLabels.value = [];
  toggleLabelSuggestions();
};

const acceptSuggestedLabels = async labels => {
  const titles = labels.map(({ title }) => title);
  await onUpdateLabels([...savedLabels.value, ...titles]);
  if (titles.every(title => savedLabels.value.includes(title))) return;

  // The save failed and the store rolled the labels back, so bring the
  // suggestions back instead of leaving them dismissed.
  useAlert(t('CONVERSATION.SUGGESTIONS.APPLY_ERROR'));
  if (!isLabelSuggestionActive.value) toggleLabelSuggestions();
};

const rejectSuggestedLabel = ({ title }) => {
  rejectedLabels.value.push(title);
};
</script>

<template>
  <div>
    <div>
      <ContactDetailsItem
        compact
        :title="$t('CONVERSATION_SIDEBAR.ASSIGNEE_LABEL')"
      >
        <template #button>
          <NextButton
            v-if="showSelfAssign"
            link
            xs
            icon="i-lucide-arrow-right"
            class="!gap-1"
            :label="$t('CONVERSATION_SIDEBAR.SELF_ASSIGN')"
            @click="onSelfAssign"
          />
        </template>
      </ContactDetailsItem>
      <MultiselectDropdown
        button-variant="outline"
        show-chevron
        :options="agentsList"
        :selected-item="assignedAgent"
        :multiselector-title="$t('AGENT_MGMT.MULTI_SELECTOR.TITLE.AGENT')"
        :multiselector-placeholder="$t('AGENT_MGMT.MULTI_SELECTOR.PLACEHOLDER')"
        :no-search-result="
          $t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.NO_RESULTS.AGENT')
        "
        :input-placeholder="
          $t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.PLACEHOLDER.AGENT')
        "
        @select="onClickAssignAgent"
      />
    </div>
    <div v-if="isAdmin">
      <ContactDetailsItem
        compact
        :title="$t('CONVERSATION.ACCESS_CONTROL.LABEL')"
      />
      <OnClickOutside @trigger="closeAccessDropdown">
        <div class="relative mb-2">
          <NextButton
            slate
            outline
            trailing-icon
            :icon="
              isAccessDropdownOpen
                ? 'i-lucide-chevron-up'
                : 'i-lucide-chevron-down'
            "
            class="w-full !px-2"
            :is-loading="isAccessLoading || isAccessSaving"
            @click="toggleAccessDropdown"
          >
            <div class="flex w-full min-w-0 items-center justify-between gap-2">
              <span
                class="min-w-0 overflow-hidden text-sm truncate text-n-slate-12"
                :title="accessSummaryLabel"
              >
                {{ accessSummaryLabel }}
              </span>
              <span
                v-if="hasRevokedAccessUsers"
                class="inline-flex items-center rounded-full bg-n-amber-5 px-1.5 py-0.5 text-[10px] font-medium text-n-amber-12"
              >
                <Icon icon="i-lucide-triangle-alert" class="size-3" />
              </span>
            </div>
          </NextButton>

          <div
            v-if="isAccessDropdownOpen"
            class="absolute left-0 right-0 top-[calc(100%+0.5rem)] z-20 overflow-hidden rounded-xl border border-n-strong bg-n-alpha-3 p-2 shadow-lg backdrop-blur-[80px]"
          >
            <div class="flex items-center justify-between gap-2 pb-2">
              <h4 class="m-0 text-sm font-medium text-n-slate-12">
                {{ $t('CONVERSATION.ACCESS_CONTROL.LABEL') }}
              </h4>
              <button
                type="button"
                class="rounded-md p-1 text-n-slate-11 transition-colors hover:bg-n-slate-2"
                @click="closeAccessDropdown"
              >
                <Icon icon="i-lucide-x" class="size-4" />
              </button>
            </div>

            <div class="flex items-center gap-1.5 pb-2">
              <NextButton
                xs
                faded
                :solid="!isAdminsOnly"
                :blue="!isAdminsOnly"
                :slate="isAdminsOnly"
                :label="$t('CONVERSATION.ACCESS_CONTROL.MODE.ALL_AGENTS')"
                @click="setAccessMode('all_agents')"
              />
              <NextButton
                xs
                faded
                :solid="isAdminsOnly"
                :blue="isAdminsOnly"
                :slate="!isAdminsOnly"
                :label="$t('CONVERSATION.ACCESS_CONTROL.MODE.ADMINS_ONLY')"
                @click="setAccessMode('admins_only')"
              />
            </div>

            <div
              v-if="!isAdminsOnly && selectedAccessUsers.length"
              class="mb-2 flex flex-wrap gap-1.5"
            >
              <button
                v-for="user in selectedAccessUsers"
                :key="user.id"
                type="button"
                class="inline-flex max-w-full items-center gap-1 rounded-lg border px-2 py-1 text-xs font-medium transition-colors"
                :class="
                  user.isRevoked
                    ? 'border-n-amber-7 bg-n-amber-5 text-n-amber-12'
                    : 'border-n-strong bg-n-slate-3 text-n-slate-12 hover:bg-n-slate-2'
                "
                :title="accessChipTitle(user)"
                @click="onToggleAccessUser(user)"
              >
                <Avatar
                  :src="user.thumbnail"
                  :name="user.name"
                  :size="16"
                  hide-offline-status
                  rounded-full
                />
                <span class="min-w-0 truncate">{{ user.name }}</span>
                <Icon
                  :icon="
                    user.isRevoked ? 'i-lucide-triangle-alert' : 'i-lucide-x'
                  "
                  class="size-3.5 flex-shrink-0"
                />
              </button>
            </div>

            <div
              v-if="!isAdminsOnly"
              class="max-h-72 space-y-1 overflow-auto pr-1"
            >
              <button
                v-for="user in filteredEligibleAccessUsers"
                :key="user.id"
                type="button"
                class="flex w-full items-center gap-2 rounded-lg px-2 py-2 text-left transition-colors hover:bg-n-slate-2"
                :class="
                  selectedAccessUserIds.includes(user.id) ? 'bg-n-slate-2' : ''
                "
                @click="onToggleAccessUser(user)"
              >
                <Avatar
                  :src="user.thumbnail"
                  :name="user.name"
                  :size="24"
                  hide-offline-status
                  rounded-full
                />
                <div class="min-w-0 flex-1">
                  <div class="truncate text-sm text-n-slate-12">
                    {{ user.name }}
                  </div>
                </div>
                <Icon
                  v-if="selectedAccessUserIds.includes(user.id)"
                  icon="i-lucide-check"
                  class="size-4 flex-shrink-0 text-n-brand"
                />
              </button>

              <div
                v-if="!filteredEligibleAccessUsers.length"
                class="px-2 py-3 text-sm text-n-slate-10"
              >
                {{ $t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.NO_RESULTS.AGENT') }}
              </div>
            </div>
          </div>
        </div>
      </OnClickOutside>
    </div>
    <div>
      <ContactDetailsItem
        compact
        :title="$t('CONVERSATION_SIDEBAR.TEAM_LABEL')"
      />
      <MultiselectDropdown
        button-variant="outline"
        show-chevron
        :options="teamsList"
        :selected-item="assignedTeam"
        show-emoji-icon
        :multiselector-title="$t('AGENT_MGMT.MULTI_SELECTOR.TITLE.TEAM')"
        :multiselector-placeholder="$t('AGENT_MGMT.MULTI_SELECTOR.PLACEHOLDER')"
        :no-search-result="
          $t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.NO_RESULTS.TEAM')
        "
        :input-placeholder="
          $t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.PLACEHOLDER.TEAM')
        "
        @select="onClickAssignTeam"
      />
    </div>
    <div>
      <ContactDetailsItem compact :title="$t('CONVERSATION.PRIORITY.TITLE')">
        <template #button>
          <SuggestButton
            v-if="isSuggestionsEnabled"
            :is-active="isPrioritySuggestionActive"
            :is-loading="isSuggestingPriority"
            @click="suggestPriority"
          />
        </template>
      </ContactDetailsItem>
      <Transition
        mode="out-in"
        enter-active-class="transition duration-200 ease-out"
        enter-from-class="opacity-0 scale-[0.98]"
        leave-active-class="transition duration-150 ease-in"
        leave-to-class="opacity-0 scale-[0.98]"
      >
        <SuggestionSkeleton
          v-if="isSuggestingPriority"
          class="w-full h-10 mb-2 rounded-lg"
        />
        <div
          v-else-if="isPrioritySuggestionActive && suggestedPriority"
          class="relative flex items-center w-full h-10 gap-2 mb-2 overflow-hidden text-sm font-medium transition-all duration-100 ease-out rounded-lg outline outline-1 outline-n-iris-6 bg-n-iris-2 hover:bg-n-iris-3 group before:absolute before:inset-0 before:bg-gradient-to-r before:from-transparent before:via-white/50 dark:before:via-white/5 before:to-transparent before:animate-shimmer before:pointer-events-none"
        >
          <button
            v-tooltip.top="$t('CONVERSATION.SUGGESTIONS.APPLY_HINT')"
            type="button"
            class="flex items-center flex-1 h-full min-w-0 gap-2 p-0 text-sm font-medium rounded-lg outline-none ps-2 text-n-slate-11 focus-visible:outline-2 focus-visible:outline-n-brand focus-visible:-outline-offset-2"
            @click="acceptSuggestedPriority"
          >
            <Icon
              icon="i-ph-sparkle-fill"
              class="flex-shrink-0 text-n-iris-9"
            />
            <template v-if="assignedPriority.id">
              <span class="inline-flex items-center gap-1.5 text-n-slate-10">
                <Icon :icon="assignedPriority.icon" class="opacity-60" />
                <span class="line-through decoration-n-slate-9">
                  {{ assignedPriority.name }}
                </span>
              </span>
              <Icon
                icon="i-lucide-arrow-right"
                class="flex-shrink-0 text-n-iris-9 transition-transform group-hover:translate-x-0.5"
              />
            </template>
            <span
              class="inline-flex items-center gap-1.5 font-semibold text-n-slate-12"
            >
              <Icon :icon="suggestedPriority.icon" />
              {{ suggestedPriority.name }}
            </span>
          </button>
          <button
            v-tooltip.top="$t('CONVERSATION.SUGGESTIONS.REJECT')"
            type="button"
            class="flex items-center justify-center flex-shrink-0 p-0 text-sm transition-all rounded-md outline-none opacity-0 me-2 size-6 text-n-slate-11 group-hover:opacity-100 focus-visible:opacity-100 hover:bg-n-iris-4 hover:text-n-slate-12 focus-visible:outline-2 focus-visible:outline-n-brand focus-visible:outline-offset-0"
            @click="dismissPrioritySuggestion"
          >
            <Icon icon="i-lucide-x" />
          </button>
        </div>
        <MultiselectDropdown
          v-else
          button-variant="outline"
          show-chevron
          :options="priorityOptions"
          :selected-item="assignedPriority"
          :multiselector-title="$t('CONVERSATION.PRIORITY.TITLE')"
          :multiselector-placeholder="
            $t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.SELECT_PLACEHOLDER')
          "
          :no-search-result="
            $t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.NO_RESULTS')
          "
          :input-placeholder="
            $t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.INPUT_PLACEHOLDER')
          "
          @select="onClickAssignPriority"
        />
      </Transition>
      <span
        v-if="
          isPrioritySuggestionActive &&
          !isSuggestingPriority &&
          !suggestedPriority
        "
        class="inline-flex items-center gap-1 mb-2 -mt-1 text-xs text-n-slate-11 animate-fade-in-up"
      >
        <Icon icon="i-ph-sparkle-fill" class="text-n-iris-9" />
        {{ $t('CONVERSATION.SUGGESTIONS.EMPTY') }}
      </span>
    </div>
    <ContactDetailsItem
      compact
      :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_LABELS')"
    >
      <template #button>
        <SuggestButton
          v-if="isSuggestionsEnabled"
          :is-active="isLabelSuggestionActive"
          :is-loading="isSuggestingLabels"
          @click="suggestLabels"
        />
      </template>
    </ContactDetailsItem>
    <ConversationLabels
      :conversation-id="conversationId"
      :suggested-labels="suggestedLabels"
      :is-suggestion-active="isLabelSuggestionActive"
      :is-suggesting="isSuggestingLabels"
      @accept-suggestion="acceptSuggestedLabels([$event])"
      @reject-suggestion="rejectSuggestedLabel"
      @accept-all-suggestions="acceptSuggestedLabels(suggestedLabels)"
    />
  </div>
</template>
