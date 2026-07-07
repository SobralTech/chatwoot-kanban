<script setup>
import { computed } from 'vue';
import { frontendURL } from 'dashboard/helper/URLHelper';

import CardLayout from 'dashboard/components-next/CardLayout.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  id: {
    type: [String, Number],
    default: 0,
  },
  name: {
    type: String,
    default: '',
  },
  thumbnail: {
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
  <router-link :to="navigateTo" class="block w-full min-w-0">
    <CardLayout
      layout="col"
      class="[&>div]:px-3 [&>div]:py-2.5 hover:bg-n-slate-2 dark:hover:bg-n-solid-3"
    >
      <div class="flex items-center gap-2.5 min-w-0 w-full">
        <Avatar
          :name="name"
          :src="thumbnail"
          :size="24"
          rounded-full
          class="flex-shrink-0"
        />
        <h5
          class="m-0 text-sm font-medium truncate min-w-0 flex-1 text-n-slate-12"
        >
          {{ name }}
        </h5>
      </div>
    </CardLayout>
  </router-link>
</template>
