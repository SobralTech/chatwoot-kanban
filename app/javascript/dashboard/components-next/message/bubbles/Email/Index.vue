<script setup>
import { computed, useTemplateRef, ref, onMounted } from 'vue';
import { sanitizeTextForRender } from '@chatwoot/utils';
import { allowedCssProperties, sanitize } from 'lettersanitizer';

import Icon from 'next/icon/Icon.vue';
import { EmailQuoteExtractor } from 'dashboard/helper/emailQuoteExtractor.js';
import FormattedContent from 'next/message/bubbles/Text/FormattedContent.vue';
import BaseBubble from 'next/message/bubbles/Base.vue';
import AttachmentChips from 'next/message/chips/AttachmentChips.vue';
import EmailMeta from './EmailMeta.vue';
import TranslationToggle from 'dashboard/components-next/message/TranslationToggle.vue';
import { highlightSearchTerm } from 'shared/helpers/highlightSearchTerm.js';

import { useMessageContext } from '../../provider.js';
import { MESSAGE_TYPES } from 'next/message/constants.js';
import { useTranslations } from 'dashboard/composables/useTranslations';

const {
  content,
  contentAttributes,
  attachments,
  messageType,
  conversationSearchQuery,
} = useMessageContext();

const isExpandable = ref(false);
const isExpanded = ref(false);
const showQuotedMessage = ref(false);
const renderOriginal = ref(false);
const contentContainer = useTemplateRef('contentContainer');
const emailAllowedCssProperties = [
  ...allowedCssProperties,
  'transform',
  'transform-origin',
];
const emailContentClass =
  'prose prose-bubble !max-w-none letter-render [&_.conversation-search-highlight]:bg-n-amber-5 [&_.conversation-search-highlight]:text-n-slate-12 [&_.conversation-search-highlight]:rounded-sm [&_.conversation-search-highlight]:px-0.5';

onMounted(() => {
  isExpandable.value = contentContainer.value?.scrollHeight > 400;
});

const isOutgoing = computed(() => messageType.value === MESSAGE_TYPES.OUTGOING);
const isIncoming = computed(() => !isOutgoing.value);

const { hasTranslations, translationContent } =
  useTranslations(contentAttributes);

const originalEmailText = computed(() => {
  const text =
    contentAttributes?.value?.email?.textContent?.full ?? content.value;
  return sanitizeTextForRender(text);
});

const originalEmailHtml = computed(
  () =>
    contentAttributes?.value?.email?.htmlContent?.full ||
    originalEmailText.value
);

const hasEmailContent = computed(() => {
  return (
    contentAttributes?.value?.email?.textContent?.full ||
    contentAttributes?.value?.email?.htmlContent?.full
  );
});

const messageContent = computed(() => {
  // If translations exist and we're showing translations (not original)
  if (hasTranslations.value && !renderOriginal.value) {
    return translationContent.value;
  }
  // Otherwise show original content
  return content.value;
});

const textToShow = computed(() => {
  // If translations exist and we're showing translations (not original)
  if (hasTranslations.value && !renderOriginal.value) {
    return translationContent.value;
  }
  // Otherwise show original text
  return originalEmailText.value;
});

const fullHTML = computed(() => {
  // If translations exist and we're showing translations (not original)
  if (hasTranslations.value && !renderOriginal.value) {
    return translationContent.value;
  }
  // Otherwise show original HTML
  return originalEmailHtml.value;
});

const unquotedHTML = computed(() =>
  EmailQuoteExtractor.extractQuotes(fullHTML.value)
);

const hasQuotedMessage = computed(() =>
  EmailQuoteExtractor.hasQuotes(fullHTML.value)
);

const renderEmailHTML = html => {
  const sanitizedHTML = sanitize(html, textToShow.value, {
    allowedCssProperties: emailAllowedCssProperties,
  });

  return highlightSearchTerm(
    sanitizedHTML,
    conversationSearchQuery.value,
    'conversation-search-highlight'
  );
};

const highlightedFullHTML = computed(() => renderEmailHTML(fullHTML.value));

const highlightedUnquotedHTML = computed(() =>
  renderEmailHTML(unquotedHTML.value)
);

// Ensure unique keys when toggling between original and translated views.
// This forces Vue to re-render the email HTML and update content correctly.
const translationKeySuffix = computed(() => {
  if (renderOriginal.value) return 'original';
  if (hasTranslations.value) return 'translated';
  return 'original';
});

const handleSeeOriginal = () => {
  renderOriginal.value = !renderOriginal.value;
};
</script>

<template>
  <BaseBubble
    class="w-full"
    :class="{
      'bg-n-slate-4': isIncoming,
      'bg-n-solid-blue': isOutgoing,
    }"
    data-bubble-name="email"
  >
    <EmailMeta
      class="p-3"
      :class="{
        'border-b border-n-strong': isIncoming,
        'border-b border-n-slate-8/20': isOutgoing,
      }"
    />
    <section ref="contentContainer" class="p-3">
      <div
        :class="{
          'max-h-[400px] overflow-hidden relative': !isExpanded && isExpandable,
          'overflow-y-scroll relative': isExpanded,
        }"
      >
        <div
          v-if="isExpandable && !isExpanded"
          class="absolute left-0 right-0 bottom-0 h-40 px-8 flex items-end"
          :class="{
            'bg-gradient-to-t from-n-slate-4 via-n-slate-4 via-20% to-transparent':
              isIncoming,
            'bg-gradient-to-t from-n-solid-blue via-n-solid-blue via-20% to-transparent':
              isOutgoing,
          }"
        >
          <button
            class="text-n-slate-12 py-2 px-8 mx-auto text-center flex items-center gap-2"
            @click="isExpanded = true"
          >
            <Icon icon="i-lucide-maximize-2" />
            {{ $t('EMAIL_HEADER.EXPAND') }}
          </button>
        </div>
        <FormattedContent
          v-if="isOutgoing && content && !hasEmailContent"
          class="text-n-slate-12"
          :content="messageContent"
        />
        <template v-else>
          <div
            v-if="showQuotedMessage"
            :key="`letter-quoted-${translationKeySuffix}`"
            :class="emailContentClass"
            v-html="highlightedFullHTML"
          />
          <div
            v-else
            :key="`letter-unquoted-${translationKeySuffix}`"
            :class="emailContentClass"
            v-html="highlightedUnquotedHTML"
          />
        </template>
        <button
          v-if="hasQuotedMessage"
          class="text-n-slate-11 px-1 leading-none text-sm bg-n-alpha-black2 text-center flex items-center gap-1 mt-2"
          @click="showQuotedMessage = !showQuotedMessage"
        >
          <template v-if="showQuotedMessage">
            {{ $t('CHAT_LIST.HIDE_QUOTED_TEXT') }}
          </template>
          <template v-else>
            {{ $t('CHAT_LIST.SHOW_QUOTED_TEXT') }}
          </template>
          <Icon
            :icon="
              showQuotedMessage
                ? 'i-lucide-chevron-up'
                : 'i-lucide-chevron-down'
            "
          />
        </button>
      </div>
    </section>
    <TranslationToggle
      v-if="hasTranslations"
      class="py-2 px-3"
      :showing-original="renderOriginal"
      @toggle="handleSeeOriginal"
    />
    <section
      v-if="Array.isArray(attachments) && attachments.length"
      class="px-4 pb-4 space-y-2"
    >
      <AttachmentChips :attachments="attachments" class="gap-1" />
    </section>
  </BaseBubble>
</template>

<style lang="scss">
// Tailwind resets break the rendering of google drive link in Gmail messages
// This fixes it using https://developer.mozilla.org/en-US/docs/Web/CSS/Attribute_selectors

.letter-render [class*='gmail_drive_chip'] {
  box-sizing: initial;
  @apply bg-n-slate-4 border-n-slate-6 rounded-md !important;

  a {
    @apply text-n-slate-12 !important;

    img {
      display: inline-block;
    }
  }
}

// Email clients (Gmail, Outlook) hardcode dir="ltr" on wrapper elements.
// In RTL apps this forces email content LTR regardless of actual text.
[dir='rtl'] .letter-render [dir='ltr'] {
  direction: inherit;
}
</style>
