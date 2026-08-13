<script>
import { ref } from 'vue';
import { mapGetters } from 'vuex';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useConversationLabels } from 'dashboard/composables/useConversationLabels';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import Spinner from 'shared/components/Spinner.vue';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
import AddLabel from 'shared/components/ui/dropdown/AddLabel.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    Spinner,
    LabelDropdown,
    AddLabel,
    NextButton,
  },
  props: {
    compact: {
      type: Boolean,
      default: false,
    },
  },
  setup() {
    const { isAdmin } = useAdmin();

    const {
      savedLabels,
      activeLabels,
      accountLabels,
      addLabelToConversation,
      removeLabelFromConversation,
    } = useConversationLabels();

    const showSearchDropdownLabel = ref(false);

    const toggleLabels = () => {
      showSearchDropdownLabel.value = !showSearchDropdownLabel.value;
    };

    const closeDropdownLabel = () => {
      showSearchDropdownLabel.value = false;
    };

    const keyboardEvents = {
      KeyL: {
        action: e => {
          e.preventDefault();
          toggleLabels();
        },
      },
      Escape: {
        action: () => {
          if (showSearchDropdownLabel.value) {
            toggleLabels();
          }
        },
        allowOnFocusedInput: true,
      },
    };
    useKeyboardEvents(keyboardEvents);
    return {
      isAdmin,
      savedLabels,
      activeLabels,
      accountLabels,
      addLabelToConversation,
      removeLabelFromConversation,
      showSearchDropdownLabel,
      closeDropdownLabel,
      toggleLabels,
    };
  },
  data() {
    return {
      selectedLabels: [],
    };
  },

  computed: {
    ...mapGetters({
      conversationUiFlags: 'conversationLabels/getUIFlags',
    }),
    compactLabelCount() {
      return this.activeLabels.length || '';
    },
    labelButtonTooltip() {
      return this.activeLabels.length
        ? this.activeLabels.map(label => label.title).join(', ')
        : this.$t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_LABELS');
    },
  },
};
</script>

<template>
  <div class="sidebar-labels-wrap" :class="{ relative: compact }">
    <div
      v-if="!conversationUiFlags.isFetching"
      class="contact-conversation--list"
      :class="{ '!w-auto': compact }"
    >
      <div
        v-on-clickaway="closeDropdownLabel"
        class="label-wrap"
        :class="compact ? 'relative' : 'flex flex-wrap'"
        @keyup.esc="closeDropdownLabel"
      >
        <NextButton
          v-if="compact"
          v-tooltip="labelButtonTooltip"
          slate
          size="sm"
          ghost
          icon="i-lucide-tag"
          :label="compactLabelCount"
          @click="toggleLabels"
        />
        <template v-else>
          <AddLabel @add="toggleLabels" />
          <woot-label
            v-for="label in activeLabels"
            :key="label.id"
            :title="label.title"
            :description="label.description"
            show-close
            :color="label.color"
            variant="smooth"
            class="max-w-[calc(100%-0.5rem)]"
            @remove="removeLabelFromConversation"
          />
        </template>
        <div
          :class="[
            {
              'block visible': showSearchDropdownLabel,
              'hidden invisible': !showSearchDropdownLabel,
            },
            compact
              ? 'right-0 top-8 w-80 max-w-[calc(100vw-2rem)]'
              : 'top-6 w-full',
          ]"
          class="border rounded-lg bg-n-alpha-3 backdrop-blur-[100px] absolute shadow-lg border-n-strong dark:border-n-strong p-2 box-border z-[9999]"
        >
          <LabelDropdown
            v-if="showSearchDropdownLabel"
            :account-labels="accountLabels"
            :selected-labels="savedLabels"
            :allow-creation="isAdmin"
            @add="addLabelToConversation"
            @remove="removeLabelFromConversation"
          />
        </div>
      </div>
    </div>
    <Spinner v-else />
  </div>
</template>

<style lang="scss" scoped>
.sidebar-labels-wrap {
  margin-bottom: 0;
}
.contact-conversation--list {
  width: 100%;

  .label-wrap {
    line-height: 1.5rem;
    position: relative;
  }
}
</style>
