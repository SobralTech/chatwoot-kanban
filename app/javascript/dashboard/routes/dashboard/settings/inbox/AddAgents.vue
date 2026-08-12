<script>
/* eslint no-console: 0 */
import { useAlert } from 'dashboard/composables';

import InboxMembersAPI from '../../../../api/inboxMembers';
import NextButton from 'dashboard/components-next/button/Button.vue';
import AgentTagInput from 'dashboard/components-next/taginput/AgentTagInput.vue';
import router from '../../../index';
import PageHeader from '../SettingsSubPageHeader.vue';
import { useVuelidate } from '@vuelidate/core';

export default {
  components: {
    PageHeader,
    NextButton,
    AgentTagInput,
  },
  validations: {
    selectedAgentIds: {
      isEmpty() {
        return !!this.selectedAgentIds.length;
      },
    },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      selectedAgentIds: [],
      isCreating: false,
    };
  },
  mounted() {
    this.$store.dispatch('agents/get');
  },
  methods: {
    async addAgents() {
      this.isCreating = true;
      const inboxId = this.$route.params.inbox_id;

      try {
        await InboxMembersAPI.update({
          inboxId,
          agentList: this.selectedAgentIds,
        });
        router.replace({
          name: 'settings_inbox_finish',
          params: {
            page: 'new',
            inbox_id: this.$route.params.inbox_id,
          },
        });
      } catch (error) {
        useAlert(error.message);
      }
      this.isCreating = false;
    },
  },
};
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <form class="flex flex-wrap flex-col mx-0" @submit.prevent="addAgents()">
      <div class="w-full">
        <PageHeader
          :header-title="$t('INBOX_MGMT.ADD.AGENTS.TITLE')"
          :header-content="$t('INBOX_MGMT.ADD.AGENTS.DESC')"
        />
      </div>
      <div>
        <div class="w-full mb-4">
          <label :class="{ error: v$.selectedAgentIds.$error }">
            {{ $t('INBOX_MGMT.ADD.AGENTS.TITLE') }}
            <AgentTagInput
              v-model="selectedAgentIds"
              :placeholder="$t('INBOX_MGMT.ADD.AGENTS.PICK_AGENTS')"
            />
            <span v-if="v$.selectedAgentIds.$error" class="message">
              {{ $t('INBOX_MGMT.ADD.AGENTS.VALIDATION_ERROR') }}
            </span>
          </label>
        </div>
        <div class="w-full">
          <NextButton
            type="submit"
            :is-loading="isCreating"
            solid
            blue
            :label="$t('INBOX_MGMT.AGENTS.BUTTON_TEXT')"
          />
        </div>
      </div>
    </form>
  </div>
</template>
