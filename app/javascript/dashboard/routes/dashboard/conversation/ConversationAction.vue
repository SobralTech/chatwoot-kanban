<!-- eslint-disable vue/v-slot-style -->
<script>
import { OnClickOutside } from '@vueuse/components';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAgentsList } from 'dashboard/composables/useAgentsList';
import Avatar from 'next/avatar/Avatar.vue';
import ContactDetailsItem from './ContactDetailsItem.vue';
import ConversationApi from '../../../api/inbox/conversation';
import MultiselectDropdown from 'shared/components/ui/MultiselectDropdown.vue';
import ConversationLabels from './labels/LabelBox.vue';
import { CONVERSATION_PRIORITY } from '../../../../shared/constants/messages';
import { CONVERSATION_EVENTS } from '../../../helper/AnalyticsHelper/events';
import { useTrack } from 'dashboard/composables';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    ContactDetailsItem,
    OnClickOutside,
    Avatar,
    Icon,
    MultiselectDropdown,
    ConversationLabels,
    NextButton,
  },
  props: {
    conversationId: {
      type: [Number, String],
      required: true,
    },
  },
  setup() {
    const { agentsList } = useAgentsList();
    const { isAdmin } = useAdmin();
    return {
      agentsList,
      isAdmin,
    };
  },
  data() {
    return {
      priorityOptions: [
        {
          id: null,
          name: this.$t('CONVERSATION.PRIORITY.OPTIONS.NONE'),
          icon: 'i-woot-priority-empty',
        },
        {
          id: CONVERSATION_PRIORITY.URGENT,
          name: this.$t('CONVERSATION.PRIORITY.OPTIONS.URGENT'),
          icon: 'i-woot-priority-urgent',
        },
        {
          id: CONVERSATION_PRIORITY.HIGH,
          name: this.$t('CONVERSATION.PRIORITY.OPTIONS.HIGH'),
          icon: 'i-woot-priority-high',
        },
        {
          id: CONVERSATION_PRIORITY.MEDIUM,
          name: this.$t('CONVERSATION.PRIORITY.OPTIONS.MEDIUM'),
          icon: 'i-woot-priority-medium',
        },
        {
          id: CONVERSATION_PRIORITY.LOW,
          name: this.$t('CONVERSATION.PRIORITY.OPTIONS.LOW'),
          icon: 'i-woot-priority-low',
        },
      ],
      accessUsers: [],
      eligibleAccessUsers: [],
      accessMode: 'all_agents',
      accessSearchQuery: '',
      isAccessDropdownOpen: false,
      isAccessLoading: false,
      isAccessSaving: false,
    };
  },
  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
      currentUser: 'getCurrentUser',
      teams: 'teams/getTeams',
    }),
    hasAnAssignedTeam() {
      return !!this.currentChat?.meta?.team;
    },
    teamsList() {
      if (this.hasAnAssignedTeam) {
        return [
          { id: 0, name: this.$t('TEAMS_SETTINGS.LIST.NONE') },
          ...this.teams,
        ];
      }
      return this.teams;
    },
    assignedAgent: {
      get() {
        return this.currentChat.meta.assignee;
      },
      set(agent) {
        const agentId = agent ? agent.id : null;
        this.$store.dispatch('setCurrentChatAssignee', {
          conversationId: this.currentChat.id,
          assignee: agent,
        });
        this.$store
          .dispatch('assignAgent', {
            conversationId: this.currentChat.id,
            agentId,
          })
          .then(() => {
            useAlert(this.$t('CONVERSATION.CHANGE_AGENT'));
          });
      },
    },
    assignedTeam: {
      get() {
        return this.currentChat.meta.team;
      },
      set(team) {
        const conversationId = this.currentChat.id;
        const teamId = team ? team.id : 0;
        this.$store.dispatch('setCurrentChatTeam', { team, conversationId });
        this.$store
          .dispatch('assignTeam', { conversationId, teamId })
          .then(() => {
            useAlert(this.$t('CONVERSATION.CHANGE_TEAM'));
          });
      },
    },
    assignedPriority: {
      get() {
        const selectedOption = this.priorityOptions.find(
          opt => opt.id === this.currentChat.priority
        );

        return selectedOption || this.priorityOptions[0];
      },
      set(priorityItem) {
        const conversationId = this.currentChat.id;
        const oldValue = this.currentChat?.priority;
        const priority = priorityItem.id;

        this.$store.dispatch('setCurrentChatPriority', {
          priority,
          conversationId,
        });
        this.$store
          .dispatch('assignPriority', { conversationId, priority })
          .then(() => {
            useTrack(CONVERSATION_EVENTS.CHANGE_PRIORITY, {
              oldValue,
              newValue: priority,
              from: 'Conversation Sidebar',
            });
            useAlert(
              this.$t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.SUCCESSFUL', {
                priority: priorityItem.name,
                conversationId,
              })
            );
          });
      },
    },
    showSelfAssign() {
      if (!this.assignedAgent) {
        return true;
      }
      if (this.assignedAgent.id !== this.currentUser.id) {
        return true;
      }
      return false;
    },
    accessUsersById() {
      return new Map(this.eligibleAccessUsers.map(user => [user.id, user]));
    },
    selectedAccessUsers() {
      return this.accessUsers.map(user => {
        const eligibleUser = this.accessUsersById.get(user.id);

        return {
          ...(eligibleUser || {}),
          ...user,
          isRevoked: !eligibleUser,
        };
      });
    },
    selectedAccessUserIds() {
      return this.selectedAccessUsers.map(user => user.id);
    },
    hasAccessUsers() {
      return this.selectedAccessUsers.length > 0;
    },
    hasRevokedAccessUsers() {
      return this.selectedAccessUsers.some(user => user.isRevoked);
    },
    isAdminsOnly() {
      return this.accessMode === 'admins_only';
    },
    accessSummaryLabel() {
      if (this.isAdminsOnly) {
        return this.$t('CONVERSATION.ACCESS_CONTROL.ADMINS_ONLY');
      }

      if (!this.selectedAccessUsers.length) {
        return this.$t('CONVERSATION.ACCESS_CONTROL.ALL_AGENTS');
      }

      const names = this.selectedAccessUsers.map(user => user.name);
      if (names.length <= 2) {
        return names.join(', ');
      }

      return `${names.slice(0, 2).join(', ')}...`;
    },
    filteredEligibleAccessUsers() {
      const searchQuery = this.accessSearchQuery.trim().toLowerCase();

      return this.eligibleAccessUsers.filter(user => {
        if (this.selectedAccessUserIds.includes(user.id)) {
          return true;
        }

        if (!searchQuery) {
          return true;
        }

        return user.name.toLowerCase().includes(searchQuery);
      });
    },
  },
  watch: {
    conversationId: {
      immediate: true,
      handler() {
        this.fetchAccessUsers();
      },
    },
  },
  methods: {
    normalizeAccessUsers(users = []) {
      return [...new Map(users.map(user => [user.id, user])).values()]
        .filter(user => user && user.id)
        .map(user => ({
          id: user.id,
          name: user.name || user.available_name || '',
          thumbnail: user.thumbnail || user.avatar_url || '',
          availability_status: user.availability_status,
        }));
    },
    extractUsers(response) {
      const payload =
        response?.data?.payload || response?.data?.data || response?.data || [];

      return Array.isArray(payload)
        ? payload
        : payload?.users || payload?.records || [];
    },
    async fetchAccessUsers() {
      if (!this.isAdmin) return;

      this.isAccessLoading = true;

      try {
        const [selectedResponse, eligibleResponse] = await Promise.all([
          ConversationApi.getAccessUsers(this.conversationId),
          ConversationApi.getEligibleAccessUsers(this.conversationId),
        ]);

        this.accessUsers = this.normalizeAccessUsers(
          this.extractUsers(selectedResponse)
        );
        this.eligibleAccessUsers = this.normalizeAccessUsers(
          this.extractUsers(eligibleResponse)
        );
        this.accessMode = selectedResponse?.data?.access_mode || 'all_agents';
      } finally {
        this.isAccessLoading = false;
      }
    },
    openAccessDropdown() {
      this.isAccessDropdownOpen = true;
      this.accessSearchQuery = '';
    },
    closeAccessDropdown() {
      this.isAccessDropdownOpen = false;
      this.accessSearchQuery = '';
    },
    toggleAccessDropdown() {
      if (this.isAccessDropdownOpen) {
        this.closeAccessDropdown();
        return;
      }

      this.openAccessDropdown();
    },
    async persistAccessUsers(nextUsers, mode = this.accessMode) {
      this.isAccessSaving = true;
      this.accessUsers = nextUsers;
      this.accessMode = mode;

      try {
        await ConversationApi.updateAccessUsers({
          conversationId: this.conversationId,
          userIds: nextUsers.map(user => user.id),
          accessMode: mode,
        });

        await this.fetchAccessUsers();
      } finally {
        this.isAccessSaving = false;
      }
    },
    async setAccessMode(mode) {
      if (this.accessMode === mode) return;

      const nextUsers = mode === 'selected_agents' ? this.accessUsers : [];
      await this.persistAccessUsers(nextUsers, mode);
    },
    async onToggleAccessUser(user) {
      const isSelected = this.selectedAccessUserIds.includes(user.id);
      const nextUsers = isSelected
        ? this.accessUsers.filter(selectedUser => selectedUser.id !== user.id)
        : [...this.accessUsers, user];

      await this.persistAccessUsers(nextUsers, 'selected_agents');
    },
    async onRemoveAccessUser(user) {
      await this.onToggleAccessUser(user);
    },
    accessChipTitle(user) {
      return user.isRevoked
        ? this.$t('CONVERSATION.ACCESS_CONTROL.REVOKED_AGENT_TITLE', {
            name: user.name,
          })
        : user.name;
    },
    onSelfAssign() {
      const {
        account_id,
        availability_status,
        available_name,
        email,
        id,
        name,
        role,
        avatar_url,
      } = this.currentUser;
      const selfAssign = {
        account_id,
        availability_status,
        available_name,
        email,
        id,
        name,
        role,
        thumbnail: avatar_url,
      };
      this.assignedAgent = selfAssign;
    },
    onClickAssignAgent(selectedItem) {
      if (this.assignedAgent && this.assignedAgent.id === selectedItem.id) {
        this.assignedAgent = null;
      } else {
        this.assignedAgent = selectedItem;
      }
    },

    onClickAssignTeam(selectedItemTeam) {
      if (this.assignedTeam && this.assignedTeam.id === selectedItemTeam.id) {
        this.assignedTeam = null;
      } else {
        this.assignedTeam = selectedItemTeam;
      }
    },

    onClickAssignPriority(selectedPriorityItem) {
      const isSamePriority =
        this.assignedPriority &&
        this.assignedPriority.id === selectedPriorityItem.id;

      this.assignedPriority = isSamePriority
        ? this.priorityOptions[0]
        : selectedPriorityItem;
    },
  },
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
                @click="onRemoveAccessUser(user)"
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
        :options="teamsList"
        :selected-item="assignedTeam"
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
      <ContactDetailsItem compact :title="$t('CONVERSATION.PRIORITY.TITLE')" />
      <MultiselectDropdown
        button-variant="outline"
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
    </div>
    <ContactDetailsItem
      compact
      :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_LABELS')"
    />
    <ConversationLabels :conversation-id="conversationId" />
  </div>
</template>
