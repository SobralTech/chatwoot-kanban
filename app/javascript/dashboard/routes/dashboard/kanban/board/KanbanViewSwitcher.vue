<script setup>
import { computed, ref } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  activeView: {
    type: String,
    default: '',
  },
});

// Expanded order is Agenda, Dashboard, Kanban, List, which is not the order the
// routes are declared in — it is the order the views are offered to the user.
const VIEWS = [
  {
    key: 'agenda',
    routeName: 'kanban_board_agenda',
    icon: 'i-lucide-calendar-days',
    label: 'KANBAN.VIEW_SWITCHER.AGENDA',
  },
  {
    key: 'dashboard',
    routeName: 'kanban_board_dashboard',
    icon: 'i-lucide-layout-dashboard',
    label: 'KANBAN.VIEW_SWITCHER.DASHBOARD',
  },
  {
    key: 'kanban',
    routeName: 'kanban_board_show',
    icon: 'i-lucide-columns-3',
    label: 'KANBAN.VIEW_SWITCHER.KANBAN',
  },
  {
    key: 'list',
    routeName: 'kanban_board_list',
    icon: 'i-lucide-list',
    label: 'KANBAN.VIEW_SWITCHER.LIST',
  },
];

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const isOpen = ref(false);

const activeViewKey = computed(
  () =>
    props.activeView ||
    VIEWS.find(view => view.routeName === route.name)?.key ||
    'kanban'
);

const activeIcon = computed(
  () => VIEWS.find(view => view.key === activeViewKey.value).icon
);

const close = () => {
  isOpen.value = false;
};

const toggle = () => {
  isOpen.value = !isOpen.value;
};

const selectView = view => {
  close();
  if (view.key === activeViewKey.value) return;

  router.push({
    name: view.routeName,
    params: {
      accountId: route.params.accountId,
      boardId: route.params.boardId,
    },
  });
};
</script>

<template>
  <OnClickOutside class="flex-shrink-0" @trigger="close">
    <div class="relative">
      <NextButton
        data-testid="kanban-view-switcher"
        :icon="activeIcon"
        variant="ghost"
        color="slate"
        size="md"
        class="[&>span]:size-5"
        :aria-label="t('KANBAN.VIEW_SWITCHER.TOGGLE')"
        :title="t('KANBAN.VIEW_SWITCHER.TOGGLE')"
        @click="toggle"
      />
      <!-- Absolute so the four pills never enter the header's width budget,
           which the S11 layout already spends down to the pixel at 768px. -->
      <div
        v-if="isOpen"
        data-testid="kanban-view-switcher-menu"
        class="absolute top-full z-50 mt-2 flex max-w-[calc(100vw-2rem)] items-center gap-1 overflow-x-auto rounded-xl border-0 bg-n-alpha-3 p-1 shadow-lg outline outline-1 outline-n-container backdrop-blur-[100px] ltr:left-0 rtl:right-0"
      >
        <button
          v-for="view in VIEWS"
          :key="view.key"
          type="button"
          :data-testid="`kanban-view-switcher-${view.key}`"
          class="inline-flex flex-shrink-0 items-center gap-2 whitespace-nowrap rounded-lg px-3 py-2 text-sm font-medium"
          :class="
            view.key === activeViewKey
              ? 'bg-n-brand/10 text-n-brand'
              : 'text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="selectView(view)"
        >
          <i class="size-4 flex-shrink-0" :class="[view.icon]" />
          {{ t(view.label) }}
        </button>
      </div>
    </div>
  </OnClickOutside>
</template>
