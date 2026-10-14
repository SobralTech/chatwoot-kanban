import { computed } from 'vue';
import { useRoute } from 'vue-router';
import {
  frontendURL,
  conversationUrl,
  conversationListPageURL,
} from 'dashboard/helper/URLHelper';
import {
  isOnMentionsView,
  isOnUnattendedView,
  isOnArchivedView,
  isOnEmailView,
  isOnFoldersView,
} from 'dashboard/store/modules/conversations/helpers/actionHelpers';
import wootConstants from 'dashboard/constants/globals';

const resolveConversationType = name => {
  const { CONVERSATION_TYPE } = wootConstants;
  const routeArg = { route: { name } };
  if (isOnMentionsView(routeArg)) return CONVERSATION_TYPE.MENTION;
  if (isOnUnattendedView(routeArg)) return CONVERSATION_TYPE.UNATTENDED;
  if (isOnArchivedView(routeArg)) return CONVERSATION_TYPE.ARCHIVED;
  if (isOnEmailView(routeArg)) return CONVERSATION_TYPE.EMAIL;
  return '';
};

// Builds conversation and list paths that keep the active route's context.
export function useConversationRoutePath() {
  const route = useRoute();

  const buildConversationPath = (
    conversationId,
    { keepFolderScope = true } = {}
  ) => {
    const {
      params: { accountId, inbox_id: inboxId, label, teamId },
      name,
    } = route;

    const conversationType = resolveConversationType(name);

    const isOnFolder = isOnFoldersView({ route: { name } });

    return frontendURL(
      conversationUrl({
        accountId,
        activeInbox: inboxId,
        id: conversationId,
        label,
        teamId,
        foldersId: keepFolderScope && isOnFolder ? route.params.id : 0,
        conversationType,
      })
    );
  };

  const buildConversationListPath = ({
    keepFolderScope = true,
    assigneeType,
  } = {}) => {
    const {
      params: { accountId, inbox_id: inboxId, label, teamId },
      name,
    } = route;
    const conversationType = resolveConversationType(name);

    const isOnFolder = isOnFoldersView({ route: { name } });

    return conversationListPageURL({
      accountId,
      conversationType,
      customViewId: keepFolderScope && isOnFolder ? route.params.id : 0,
      inboxId,
      label,
      teamId,
      assigneeType,
    });
  };

  const isOnFolderView = computed(() =>
    isOnFoldersView({ route: { name: route.name } })
  );

  return { buildConversationPath, buildConversationListPath, isOnFolderView };
}
