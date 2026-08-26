import { frontendURL } from '../../../helper/URLHelper';
import KanbanOverview from './KanbanOverview.vue';
import KanbanView from './KanbanView.vue';
import KanbanBoardForm from './KanbanBoardForm.vue';
import KanbanBoardCreate from './KanbanBoardCreate.vue';
import ConversationView from '../conversation/ConversationView.vue';

const meta = {
  permissions: ['administrator', 'agent'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/kanban'),
    name: 'kanban_boards',
    component: KanbanOverview,
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/kanban/:boardId'),
    name: 'kanban_board_show',
    component: KanbanView,
    meta,
  },
  {
    path: frontendURL(
      'accounts/:accountId/kanban/:boardId/conversations/:conversationId'
    ),
    name: 'kanban_board_conversation',
    component: ConversationView,
    meta,
    props: route => ({
      conversationId: route.params.conversationId,
      backRoute: {
        name: 'kanban_board_show',
        params: {
          accountId: route.params.accountId,
          boardId: route.params.boardId,
        },
      },
    }),
  },
  {
    path: frontendURL('accounts/:accountId/kanban/new'),
    name: 'kanban_board_create_form',
    component: KanbanBoardCreate,
    meta: { permissions: ['administrator'] },
  },
  {
    path: frontendURL('accounts/:accountId/kanban/:boardId/edit'),
    name: 'kanban_board_edit_form',
    component: KanbanBoardForm,
    meta,
  },
];
