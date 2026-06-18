<script>
const MINUTE_IN_MILLI_SECONDS = 60000;
const HOUR_IN_MILLI_SECONDS = MINUTE_IN_MILLI_SECONDS * 60;
const DAY_IN_MILLI_SECONDS = HOUR_IN_MILLI_SECONDS * 24;

import {
  relativeDayTimestamp,
  humanTimestamp,
} from 'shared/helpers/timeHelper';

export default {
  name: 'TimeAgo',
  props: {
    isAutoRefreshEnabled: {
      type: Boolean,
      default: true,
    },
    lastActivityTimestamp: {
      type: [String, Date, Number],
      default: '',
    },
    conversationId: {
      type: [String, Number],
      default: '',
    },
  },
  data() {
    return {
      lastActivityAtTimeAgo: relativeDayTimestamp(this.lastActivityTimestamp),
      timer: null,
    };
  },
  computed: {
    lastActivityTime() {
      return this.lastActivityAtTimeAgo;
    },
    tooltipText() {
      return `Última mensagem: ${humanTimestamp(this.lastActivityTimestamp)}`;
    },
  },
  watch: {
    lastActivityTimestamp() {
      this.lastActivityAtTimeAgo = relativeDayTimestamp(
        this.lastActivityTimestamp
      );
    },
    conversationId() {
      // Reset display values and timer when the row is recycled to a different conversation.
      this.lastActivityAtTimeAgo = relativeDayTimestamp(
        this.lastActivityTimestamp
      );
      if (this.isAutoRefreshEnabled) {
        clearTimeout(this.timer);
        this.createTimer();
      }
    },
  },
  mounted() {
    if (this.isAutoRefreshEnabled) {
      this.createTimer();
    }
  },
  unmounted() {
    clearTimeout(this.timer);
  },
  methods: {
    createTimer() {
      this.timer = setTimeout(() => {
        this.lastActivityAtTimeAgo = relativeDayTimestamp(
          this.lastActivityTimestamp
        );
        this.createTimer();
      }, this.refreshTime());
    },
    refreshTime() {
      const timeDiff = Date.now() - this.lastActivityTimestamp * 1000;
      if (timeDiff > DAY_IN_MILLI_SECONDS) {
        return DAY_IN_MILLI_SECONDS;
      }
      if (timeDiff > HOUR_IN_MILLI_SECONDS) {
        return HOUR_IN_MILLI_SECONDS;
      }

      return MINUTE_IN_MILLI_SECONDS;
    },
  },
};
</script>

<template>
  <div
    v-tooltip.top="{
      content: tooltipText,
      delay: { show: 1000, hide: 0 },
    }"
    class="ml-auto leading-4 text-xxs text-n-slate-10 hover:text-n-slate-11"
  >
    <span>{{ lastActivityTime }}</span>
  </div>
</template>
