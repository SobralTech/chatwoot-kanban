<script setup>
import { computed } from 'vue';
import { frontendURL } from 'dashboard/helper/URLHelper';

import CardLayout from 'dashboard/components-next/CardLayout.vue';

const props = defineProps({
  id: {
    type: [String, Number],
    default: 0,
  },
  name: {
    type: String,
    default: '',
  },
  accountId: {
    type: [String, Number],
    default: 0,
  },
});

const navigateTo = computed(() => {
  return frontendURL(`accounts/${props.accountId}/contacts/${props.id}`);
});
</script>

<template>
  <router-link :to="navigateTo">
    <CardLayout
      layout="col"
      class="[&>div]:px-4 [&>div]:py-3 hover:bg-n-slate-2 dark:hover:bg-n-solid-3"
    >
      <h5 class="m-0 text-sm font-medium truncate min-w-0 text-n-slate-12">
        {{ name }}
      </h5>
    </CardLayout>
  </router-link>
</template>
