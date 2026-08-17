<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import { formatCurrency } from 'dashboard/helper/kanbanCurrency';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
import KanbanDueDatePicker from '../KanbanDueDatePicker.vue';

const props = defineProps({
  card: {
    type: Object,
    required: true,
  },
  accountLabels: {
    type: Array,
    default: () => [],
  },
  selectedLabelTitles: {
    type: Array,
    default: () => [],
  },
  isLoadingLabels: {
    type: Boolean,
    default: false,
  },
  labelsLoadError: {
    type: String,
    default: '',
  },
  assignedUsers: {
    type: Array,
    default: () => [],
  },
  assignableUsers: {
    type: Array,
    default: () => [],
  },
  isLoadingAssignees: {
    type: Boolean,
    default: false,
  },
  assigneesLoadError: {
    type: String,
    default: '',
  },
  totalValue: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits([
  'addLabel',
  'removeLabel',
  'toggleAssignee',
  'openConversation',
]);

const dueAt = defineModel('dueAt', {
  type: String,
  default: '',
});

const { t } = useI18n();

const hasConversation = computed(() => !!props.card.conversationId);
const inboxObject = computed(
  () => props.card.inbox || props.card.conversation?.inbox || null
);
const inboxName = computed(
  () => inboxObject.value?.name || t('KANBAN.OPPORTUNITY_DETAILS.NO_INBOX')
);
const hasContact = computed(() => !!props.card.contact);
const contactName = computed(
  () =>
    props.card.contact?.name ||
    props.card.contact?.email ||
    props.card.contact?.phoneNumber ||
    t('KANBAN.OPPORTUNITY_DETAILS.NO_CONTACT')
);
const selectedAssigneeIds = computed(() =>
  props.assignedUsers.map(user => user.id)
);
const assigneesSummary = computed(() => {
  if (!props.assignedUsers.length) {
    return t('KANBAN.OPPORTUNITY_DETAILS.UNASSIGNED');
  }

  return props.assignedUsers.map(user => user.name).join(', ');
});
const selectedLabels = computed(() =>
  props.selectedLabelTitles.map(title => {
    const accountLabel = props.accountLabels.find(
      label => label.title === title
    );
    return accountLabel || { title };
  })
);
const selectedLabelsSummary = computed(() => {
  if (!props.selectedLabelTitles.length) {
    return t('KANBAN.OPPORTUNITY_DETAILS.NO_LABELS_SELECTED');
  }

  return props.selectedLabelTitles.join(', ');
});
const formattedTotalValue = computed(() => formatCurrency(props.totalValue));

const openConversation = () => {
  if (hasConversation.value) emit('openConversation');
};
</script>

<template>
  <aside
    data-testid="kanban-opportunity-context-rail"
    class="grid min-w-0 content-start gap-4 self-start xl:sticky xl:top-0"
  >
    <section class="grid min-w-0 gap-2 rounded-lg border border-n-weak p-3">
      <h3 class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('KANBAN.OPPORTUNITY_DETAILS.CONTACT') }}
      </h3>
      <p
        data-testid="kanban-opportunity-contact"
        class="mb-0 flex min-w-0 items-center gap-2 text-sm text-n-slate-11"
      >
        <Avatar
          v-if="hasContact"
          :name="contactName"
          :src="card.contact.thumbnail"
          :size="20"
          rounded-full
        />
        <i v-else class="i-lucide-user-round size-4 flex-shrink-0" />
        <span class="min-w-0 truncate">{{ contactName }}</span>
      </p>
    </section>

    <section class="grid min-w-0 gap-3 rounded-lg border border-n-weak p-3">
      <h3 class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('KANBAN.OPPORTUNITY_DETAILS.CONVERSATION') }}
      </h3>
      <p
        v-if="hasConversation"
        data-testid="kanban-opportunity-conversation"
        class="mb-0 flex min-w-0 items-center gap-2 text-sm text-n-slate-11"
      >
        <ChannelIcon
          v-if="inboxObject"
          :inbox="inboxObject"
          class="size-4 flex-shrink-0"
        />
        <i v-else class="i-lucide-inbox size-4 flex-shrink-0" />
        <span class="min-w-0 truncate">{{ inboxName }}</span>
      </p>
      <p
        v-else
        data-testid="kanban-opportunity-no-conversation"
        class="mb-0 flex items-center gap-2 text-sm text-n-slate-11"
      >
        <i class="i-lucide-message-square-off size-4" />
        {{ t('KANBAN.OPPORTUNITY_DETAILS.NO_LINKED_CONVERSATION') }}
      </p>
      <NextButton
        v-if="hasConversation"
        type="button"
        outline
        slate
        xs
        data-testid="kanban-opportunity-open-conversation"
        icon="i-lucide-external-link"
        :label="t('KANBAN.OPPORTUNITY_DETAILS.OPEN_CONVERSATION')"
        @click="openConversation"
      />
    </section>

    <section class="grid gap-3 rounded-lg border border-n-weak p-3">
      <h3 class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('KANBAN.OPPORTUNITY_DETAILS.LABELS') }}
      </h3>
      <p
        v-if="labelsLoadError"
        data-testid="kanban-opportunity-labels-load-error"
        class="mb-0 text-sm text-n-ruby-11"
      >
        {{ labelsLoadError }}
      </p>

      <Popover align="start" disable-mobile-view :show-content-border="false">
        <button
          type="button"
          data-testid="kanban-opportunity-labels-menu"
          class="inline-flex min-h-10 w-full items-center gap-2 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-left text-sm text-n-slate-12 outline-none hover:bg-n-alpha-2 focus:border-n-brand disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="isLoadingLabels"
        >
          <i class="i-lucide-tags size-4 flex-shrink-0 text-n-slate-11" />
          <span class="min-w-0 flex-1 truncate">
            {{ selectedLabelsSummary }}
          </span>
          <i
            class="i-lucide-chevron-down size-4 flex-shrink-0 text-n-slate-11"
          />
        </button>

        <template #content>
          <div
            class="block visible w-80 rounded-lg border border-n-strong bg-n-alpha-3 p-2 shadow-lg backdrop-blur-[100px] dark:border-n-strong"
          >
            <LabelDropdown
              :account-labels="accountLabels"
              :selected-labels="selectedLabelTitles"
              allow-creation
              @add="emit('addLabel', $event)"
              @remove="emit('removeLabel', $event)"
            />
          </div>
        </template>
      </Popover>

      <div
        v-if="selectedLabels.length"
        data-testid="kanban-opportunity-labels"
        class="flex flex-wrap gap-2"
      >
        <span
          v-for="label in selectedLabels"
          :key="label.id || label.title"
          data-testid="kanban-opportunity-label"
          class="inline-flex items-center gap-2 rounded-full border border-n-weak bg-n-alpha-1 px-3 py-1 text-xs font-medium text-n-slate-11"
        >
          <span
            class="size-2 rounded-full"
            :style="{ backgroundColor: label.color }"
          />
          <span>{{ label.title }}</span>
        </span>
      </div>
      <p
        v-else-if="!isLoadingLabels && !labelsLoadError"
        data-testid="kanban-opportunity-no-labels"
        class="mb-0 text-sm text-n-slate-11"
      >
        {{ t('KANBAN.OPPORTUNITY_DETAILS.NO_LABELS_SELECTED') }}
      </p>
    </section>

    <section class="grid gap-3 rounded-lg border border-n-weak p-3">
      <h3 class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('KANBAN.OPPORTUNITY_DETAILS.ASSIGNEE') }}
      </h3>
      <p
        v-if="assigneesLoadError"
        data-testid="kanban-opportunity-assignees-load-error"
        class="mb-0 text-sm text-n-ruby-11"
      >
        {{ assigneesLoadError }}
      </p>

      <Popover align="start" disable-mobile-view :show-content-border="false">
        <button
          type="button"
          data-testid="kanban-opportunity-assignees-menu"
          class="inline-flex min-h-10 w-full items-center gap-2 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-left text-sm text-n-slate-12 outline-none hover:bg-n-alpha-2 focus:border-n-brand disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="isLoadingAssignees"
        >
          <i class="i-lucide-users size-4 flex-shrink-0 text-n-slate-11" />
          <span class="min-w-0 flex-1 truncate">
            {{ assigneesSummary }}
          </span>
          <i
            class="i-lucide-chevron-down size-4 flex-shrink-0 text-n-slate-11"
          />
        </button>

        <template #content>
          <div
            class="block visible w-72 rounded-lg border border-n-strong bg-n-alpha-3 p-2 shadow-lg backdrop-blur-[100px] dark:border-n-strong"
          >
            <ul class="grid gap-1">
              <li v-for="user in assignableUsers" :key="user.id">
                <button
                  type="button"
                  data-testid="kanban-opportunity-assignee-option"
                  :data-selected="selectedAssigneeIds.includes(user.id)"
                  class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
                  @click="emit('toggleAssignee', user)"
                >
                  <input
                    type="checkbox"
                    class="pointer-events-none"
                    :checked="selectedAssigneeIds.includes(user.id)"
                    tabindex="-1"
                  />
                  <Avatar
                    :name="user.name"
                    :src="user.avatarUrl"
                    :size="20"
                    rounded-full
                  />
                  <span class="min-w-0 flex-1 truncate">
                    {{ user.name }}
                  </span>
                </button>
              </li>
            </ul>
            <p
              v-if="!assignableUsers.length"
              class="mb-0 px-2 py-1.5 text-sm text-n-slate-11"
            >
              {{ t('KANBAN.OPPORTUNITY_DETAILS.NO_ASSIGNABLE_USERS') }}
            </p>
          </div>
        </template>
      </Popover>

      <div
        v-if="assignedUsers.length"
        data-testid="kanban-opportunity-assignees"
        class="flex flex-wrap gap-2"
      >
        <span
          v-for="user in assignedUsers"
          :key="user.id"
          data-testid="kanban-opportunity-assignee"
          class="inline-flex items-center gap-2 rounded-full border border-n-weak bg-n-alpha-1 px-3 py-1 text-xs font-medium text-n-slate-11"
        >
          <Avatar
            :name="user.name"
            :src="user.avatarUrl"
            :size="16"
            rounded-full
          />
          <span>{{ user.name }}</span>
        </span>
      </div>
      <p
        v-else-if="!isLoadingAssignees && !assigneesLoadError"
        data-testid="kanban-opportunity-no-assignees"
        class="mb-0 text-sm text-n-slate-11"
      >
        {{ t('KANBAN.OPPORTUNITY_DETAILS.UNASSIGNED') }}
      </p>
    </section>

    <section class="grid gap-4 rounded-lg border border-n-weak p-3">
      <div class="grid gap-1">
        <h3 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.TOTAL_VALUE') }}
        </h3>
        <p
          data-testid="kanban-opportunity-total-value"
          class="mb-0 text-sm text-n-slate-11"
        >
          {{ formattedTotalValue }}
        </p>
      </div>

      <KanbanDueDatePicker
        v-model="dueAt"
        data-testid="kanban-opportunity-due-at"
        :label="t('KANBAN.OPPORTUNITY_DETAILS.DUE_DATE')"
        :placeholder="t('KANBAN.OPPORTUNITY_DETAILS.CHOOSE_DATE')"
        :clear-label="t('KANBAN.OPPORTUNITY_DETAILS.CLEAR_DATE')"
      />
    </section>
  </aside>
</template>
