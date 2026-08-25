<script setup>
import { computed, h } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  createColumnHelper,
  getCoreRowModel,
  getPaginationRowModel,
  useVueTable,
} from '@tanstack/vue-table';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import Pagination from 'dashboard/components/table/Pagination.vue';
import Table from 'dashboard/components/table/Table.vue';

const props = defineProps({
  title: {
    type: String,
    required: true,
  },
  rows: {
    type: Array,
    default: () => [],
  },
  columns: {
    type: Array,
    required: true,
  },
  loading: {
    type: Boolean,
    default: false,
  },
  error: {
    type: String,
    default: '',
  },
  emptyMessage: {
    type: String,
    required: true,
  },
  downloadLabel: {
    type: String,
    required: true,
  },
  downloadLoading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['download']);
const { t } = useI18n();
const columnHelper = createColumnHelper();

const tableColumns = computed(() =>
  props.columns.map(column =>
    columnHelper.accessor(column.key, {
      header: column.label,
      size: column.size || 160,
      cell: cellProps =>
        h(
          'span',
          { class: 'text-sm text-n-slate-12' },
          cellProps.getValue() ?? t('REPORT.KANBAN.TABLE.EMPTY_VALUE')
        ),
    })
  )
);

const table = useVueTable({
  get data() {
    return props.rows;
  },
  get columns() {
    return tableColumns.value;
  },
  getCoreRowModel: getCoreRowModel(),
  getPaginationRowModel: getPaginationRowModel(),
  initialState: {
    pagination: {
      pageSize: 10,
    },
  },
});
</script>

<template>
  <section
    class="flex flex-col gap-3 overflow-hidden rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container"
  >
    <div class="flex items-center justify-between gap-3">
      <h2 class="m-0 text-base font-semibold text-n-slate-12">{{ title }}</h2>
      <Button
        :label="downloadLabel"
        icon="i-ph-download-simple"
        size="sm"
        variant="outline"
        color="slate"
        :is-loading="downloadLoading"
        :disabled="loading || downloadLoading"
        @click="emit('download')"
      />
    </div>

    <div v-if="loading" class="flex items-center justify-center gap-2 p-8">
      <Spinner />
      <span class="text-sm text-n-slate-11">{{
        t('REPORT.KANBAN.STATES.LOADING')
      }}</span>
    </div>
    <p v-else-if="error" class="m-0 p-8 text-center text-sm text-n-ruby-11">
      {{ error }}
    </p>
    <EmptyState v-else-if="!rows.length" :title="emptyMessage" />
    <template v-else>
      <div class="overflow-x-auto">
        <Table :table="table" />
      </div>
      <Pagination :table="table" />
    </template>
  </section>
</template>
