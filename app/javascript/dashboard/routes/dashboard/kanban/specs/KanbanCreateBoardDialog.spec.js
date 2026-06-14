import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import KanbanCreateBoardDialog from '../KanbanCreateBoardDialog.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => {
      const translations = {
        'KANBAN.OVERVIEW.CREATE_BOARD_MODAL_TITLE': 'Nome do funil',
        'KANBAN.ACTIONS.BOARD_NAME_PLACEHOLDER': 'Nome do quadro',
        'KANBAN.ACTIONS.CONFIRM_CREATE_BOARD': 'Criar funil',
        'KANBAN.ACTIONS.CANCEL_CREATE_BOARD': 'Cancelar criação do funil',
      };

      return translations[key] || key;
    },
  }),
}));

const mountDialog = props =>
  mount(KanbanCreateBoardDialog, {
    props: {
      modelValue: true,
      ...props,
    },
  });

describe('KanbanCreateBoardDialog', () => {
  it('confirms with Enter using only the typed board name', async () => {
    const wrapper = mountDialog();

    const input = wrapper.find(
      '[data-testid="kanban-create-board-name-input"]'
    );
    await input.setValue(' New Funnel ');
    await input.trigger('keydown', { key: 'Enter' });

    expect(wrapper.emitted('create')).toEqual([['New Funnel']]);
  });

  it('cancels with Escape and clears the typed board name', async () => {
    const wrapper = mountDialog();

    const input = wrapper.find(
      '[data-testid="kanban-create-board-name-input"]'
    );
    await input.setValue('Draft Funnel');
    await wrapper
      .find('[data-testid="kanban-create-board-dialog"]')
      .trigger('keydown', { key: 'Escape' });
    await nextTick();

    expect(wrapper.emitted('update:modelValue')).toEqual([[false]]);
    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(input.element.value).toBe('');
  });

  it('cancels with the icon button and clears the typed board name', async () => {
    const wrapper = mountDialog();

    const input = wrapper.find(
      '[data-testid="kanban-create-board-name-input"]'
    );
    await input.setValue('Draft Funnel');
    await wrapper
      .find('[data-testid="kanban-create-board-cancel"]')
      .trigger('click');

    expect(wrapper.emitted('update:modelValue')).toEqual([[false]]);
    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(input.element.value).toBe('');
  });

  it('preserves typed text when an error is shown', async () => {
    const wrapper = mountDialog();

    const input = wrapper.find(
      '[data-testid="kanban-create-board-name-input"]'
    );
    await input.setValue('Existing Funnel');
    await wrapper.setProps({ error: 'Name is already taken' });

    expect(
      wrapper.find('[data-testid="kanban-create-board-error"]').text()
    ).toBe('Name is already taken');
    expect(input.element.value).toBe('Existing Funnel');
  });
});
