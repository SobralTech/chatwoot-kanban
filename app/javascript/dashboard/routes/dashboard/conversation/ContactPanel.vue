<script setup>
import { computed, watch, onMounted, ref } from 'vue';
import {
  useMapGetter,
  useFunctionGetter,
  useStore,
} from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import {
  useUISettings,
  PINNED_CONVERSATION_SIDEBAR_ITEMS,
} from 'dashboard/composables/useUISettings';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';
import ContactConversations from './ContactConversations.vue';
import ConversationAction from './ConversationAction.vue';
import ConversationParticipant from './ConversationParticipant.vue';
import ContactInfo from './contact/ContactInfo.vue';
import ContactNotes from './contact/ContactNotes.vue';
import ConversationInfo from './ConversationInfo.vue';
import CustomAttributes from './customAttributes/CustomAttributes.vue';
import SharedFiles from './SharedFiles.vue';
import Draggable from 'vuedraggable';
import MacrosList from './Macros/List.vue';
import KanbanConversationCards from './Kanban/KanbanConversationCards.vue';
import ShopifyOrdersList from 'dashboard/components/widgets/conversation/ShopifyOrdersList.vue';
import SidebarActionsHeader from 'dashboard/components-next/SidebarActionsHeader.vue';
import LinearIssuesList from 'dashboard/components/widgets/conversation/linear/IssuesList.vue';
import LinearSetupCTA from 'dashboard/components/widgets/conversation/linear/LinearSetupCTA.vue';
import {
  useContactSidebar,
  useEmbeddedConversation,
} from 'dashboard/composables/useEmbeddedConversation';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  inboxId: {
    type: Number,
    default: undefined,
  },
});

const {
  updateUISettings,
  isContactSidebarItemOpen,
  conversationSidebarItemsOrder,
  toggleSidebarUIState,
} = useUISettings();

const dragging = ref(false);
const conversationSidebarItems = ref([]);
const embedded = useEmbeddedConversation();
const { closeSidePanels } = useContactSidebar();
// Embedded conversations are opened from a kanban board, so the kanban
// accordion starts expanded without persisting that to the UI settings.
const isEmbeddedKanbanOpen = ref(true);
const isKanbanOpen = computed(() =>
  embedded.value
    ? isEmbeddedKanbanOpen.value
    : isContactSidebarItemOpen('is_kanban_open')
);
const kanbanSummary = ref({ count: 0, staleCount: 0 });
const updateKanbanSummary = summary => {
  kanbanSummary.value = summary;
};

const shopifyIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'shopify'
);

const isShopifyFeatureEnabled = computed(
  () => shopifyIntegration.value.enabled
);

const { isCloudFeatureEnabled } = useAccount();

const isLinearFeatureEnabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.LINEAR)
);

const linearIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'linear'
);

const isLinearClientIdConfigured = computed(() => {
  return !!linearIntegration.value?.id;
});

const isLinearConnected = computed(
  () => linearIntegration.value?.enabled || false
);

const store = useStore();
const currentChat = useMapGetter('getSelectedChat');
const conversationId = computed(() => props.conversationId);
const conversationMetadataGetter = useMapGetter(
  'conversationMetadata/getConversationMetadata'
);
const currentConversationMetaData = computed(() =>
  conversationMetadataGetter.value(conversationId.value)
);
const conversationAdditionalAttributes = computed(
  () => currentConversationMetaData.value.additional_attributes || {}
);

const channelType = computed(() => currentChat.value.meta?.channel);

const contactGetter = useMapGetter('contacts/getContact');
const contactId = computed(() => currentChat.value.meta?.sender?.id);
const contact = computed(() => contactGetter.value(contactId.value));
const contactAdditionalAttributes = computed(
  () => contact.value.additional_attributes || {}
);

const getContactDetails = () => {
  if (contactId.value) {
    store.dispatch('contacts/show', { id: contactId.value });
  }
};

watch(contactId, (newContactId, prevContactId) => {
  if (newContactId && newContactId !== prevContactId) {
    getContactDetails();
  }
});

const onDragEnd = () => {
  dragging.value = false;
  updateUISettings({
    conversation_sidebar_items_order: [
      ...PINNED_CONVERSATION_SIDEBAR_ITEMS.map(name => ({ name })),
      ...conversationSidebarItems.value,
    ],
  });
};

const toggleKanban = () => {
  if (embedded.value) {
    isEmbeddedKanbanOpen.value = !isEmbeddedKanbanOpen.value;
    return;
  }

  toggleSidebarUIState('is_kanban_open');
};

onMounted(() => {
  conversationSidebarItems.value = conversationSidebarItemsOrder.value.filter(
    item => !PINNED_CONVERSATION_SIDEBAR_ITEMS.includes(item.name)
  );
  getContactDetails();
  store.dispatch('attributes/get', 0);
  // Load integrations to ensure linear integration state is available
  store.dispatch('integrations/get', 'linear');
});
</script>

<template>
  <div class="w-full">
    <SidebarActionsHeader
      :title="$t('CONVERSATION.SIDEBAR.CONTACT')"
      @close="closeSidePanels"
    />
    <ContactInfo :contact="contact" :channel-type="channelType" />
    <div class="px-2 pb-8 list-group flex flex-col gap-3">
      <div class="conversation--actions">
        <AccordionItem
          :title="$t('CONVERSATION_SIDEBAR.ACCORDION.KANBAN')"
          :is-open="isKanbanOpen"
          compact
          :draggable="false"
          @toggle="toggleKanban"
        >
          <template #button>
            <span class="ml-1 text-xs font-normal text-n-slate-10">
              {{ $t('CONVERSATION_SIDEBAR.KANBAN.SEPARATOR') }}
              {{
                $t('CONVERSATION_SIDEBAR.KANBAN.COUNT', {
                  count: kanbanSummary.count,
                })
              }}
            </span>
            <span
              v-if="kanbanSummary.staleCount"
              class="ml-1 inline-block size-2 rounded-full bg-n-ruby-9 align-middle"
              :title="
                $t('CONVERSATION_SIDEBAR.KANBAN.STALE_HINT', {
                  count: kanbanSummary.staleCount,
                })
              "
            />
          </template>
          <KanbanConversationCards
            :conversation-id="conversationId"
            @summary="updateKanbanSummary"
          />
        </AccordionItem>
      </div>
      <div class="conversation--actions">
        <AccordionItem
          :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_ACTIONS')"
          :is-open="isContactSidebarItemOpen('is_conv_actions_open')"
          :draggable="false"
          @toggle="value => toggleSidebarUIState('is_conv_actions_open', value)"
        >
          <ConversationAction
            :conversation-id="conversationId"
            :inbox-id="inboxId"
          />
        </AccordionItem>
      </div>
      <Draggable
        :list="conversationSidebarItems"
        animation="200"
        ghost-class="ghost"
        handle=".drag-handle"
        item-key="name"
        class="flex flex-col gap-3"
        @start="dragging = true"
        @end="onDragEnd"
      >
        <template #item="{ element }">
          <div
            v-if="element.name === 'conversation_participants'"
            class="conversation--actions"
          >
            <AccordionItem
              :title="$t('CONVERSATION_PARTICIPANTS.SIDEBAR_TITLE')"
              :is-open="isContactSidebarItemOpen('is_conv_participants_open')"
              @toggle="
                value =>
                  toggleSidebarUIState('is_conv_participants_open', value)
              "
            >
              <ConversationParticipant
                :conversation-id="conversationId"
                :inbox-id="inboxId"
              />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'conversation_info'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_INFO')"
              :is-open="isContactSidebarItemOpen('is_conv_details_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_conv_details_open', value)
              "
            >
              <ConversationInfo
                :conversation-attributes="conversationAdditionalAttributes"
                :contact-attributes="contactAdditionalAttributes"
              />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'contact_attributes'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_ATTRIBUTES')"
              :is-open="isContactSidebarItemOpen('is_contact_attributes_open')"
              compact
              @toggle="
                value =>
                  toggleSidebarUIState('is_contact_attributes_open', value)
              "
            >
              <CustomAttributes
                attribute-type="contact_attribute"
                attribute-from="conversation_contact_panel"
                :contact-id="contact.id"
                :empty-state-message="
                  $t('CONVERSATION_CUSTOM_ATTRIBUTES.NO_RECORDS_FOUND')
                "
              />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'previous_conversation'">
            <AccordionItem
              v-if="contact.id"
              :title="
                $t('CONVERSATION_SIDEBAR.ACCORDION.PREVIOUS_CONVERSATION')
              "
              :is-open="isContactSidebarItemOpen('is_previous_conv_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_previous_conv_open', value)
              "
            >
              <ContactConversations
                :contact-id="contact.id"
                :conversation-id="conversationId"
              />
            </AccordionItem>
          </div>
          <woot-feature-toggle
            v-else-if="element.name === 'macros'"
            feature-key="macros"
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.MACROS')"
              :is-open="isContactSidebarItemOpen('is_macro_open')"
              compact
              @toggle="value => toggleSidebarUIState('is_macro_open', value)"
            >
              <MacrosList :conversation-id="conversationId" />
            </AccordionItem>
          </woot-feature-toggle>
          <div
            v-else-if="
              element.name === 'linear_issues' &&
              isLinearFeatureEnabled &&
              isLinearClientIdConfigured
            "
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.LINEAR_ISSUES')"
              :is-open="isContactSidebarItemOpen('is_linear_issues_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_linear_issues_open', value)
              "
            >
              <LinearSetupCTA v-if="!isLinearConnected" />
              <LinearIssuesList v-else :conversation-id="conversationId" />
            </AccordionItem>
          </div>
          <div
            v-else-if="
              element.name === 'shopify_orders' && isShopifyFeatureEnabled
            "
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.SHOPIFY_ORDERS')"
              :is-open="isContactSidebarItemOpen('is_shopify_orders_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_shopify_orders_open', value)
              "
            >
              <ShopifyOrdersList :contact-id="contactId" />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'contact_notes'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_NOTES')"
              :is-open="isContactSidebarItemOpen('is_contact_notes_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_contact_notes_open', value)
              "
            >
              <ContactNotes :contact-id="contactId" />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'shared_files'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.SHARED_FILES')"
              :is-open="isContactSidebarItemOpen('is_shared_files_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_shared_files_open', value)
              "
            >
              <SharedFiles />
            </AccordionItem>
          </div>
        </template>
      </Draggable>
    </div>
  </div>
</template>

<style lang="scss" scoped>
:deep(.contact--profile) {
  @apply pb-3 border-b border-solid border-n-weak;
}
</style>
