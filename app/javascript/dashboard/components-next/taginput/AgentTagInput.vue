<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import TagInput from './TagInput.vue';

defineProps({
  placeholder: { type: String, default: '' },
  // When false, the dropdown won't auto-open on mount; it opens only on click/focus.
  autoOpenDropdown: { type: Boolean, default: true },
});

const selectedAgentIds = defineModel({ type: Array, default: () => [] });

const agents = useMapGetter('agents/getAgents');

const agentLabel = agent => agent?.name || agent?.email || '';

const selectedAgentNames = computed(() =>
  selectedAgentIds.value.map(id =>
    agentLabel(agents.value.find(agent => agent.id === id))
  )
);

const agentMenuItems = computed(() =>
  agents.value
    .filter(agent => !selectedAgentIds.value.includes(agent.id))
    .map(agent => ({
      label: agentLabel(agent),
      value: agent.id,
      action: 'select',
      thumbnail: {
        name: agentLabel(agent),
        src: agent.thumbnail || agent.avatar_url || '',
      },
    }))
);

const handleAdd = ({ value }) => {
  selectedAgentIds.value = [...selectedAgentIds.value, value];
};

const handleRemove = index => {
  selectedAgentIds.value = selectedAgentIds.value.filter(
    (_, idx) => idx !== index
  );
};
</script>

<template>
  <div
    class="rounded-xl outline outline-1 -outline-offset-1 outline-n-weak hover:outline-n-strong px-2 py-2"
  >
    <TagInput
      :model-value="selectedAgentNames"
      :placeholder="placeholder"
      :menu-items="agentMenuItems"
      show-dropdown
      skip-label-dedup
      :auto-open-dropdown="autoOpenDropdown"
      @add="handleAdd"
      @remove="handleRemove"
    />
  </div>
</template>
