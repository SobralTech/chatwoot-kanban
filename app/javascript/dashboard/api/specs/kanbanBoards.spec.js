import kanbanBoards from '../kanbanBoards';
import ApiClient from '../ApiClient';

describe('#KanbanBoardsAPI', () => {
  it('creates correct instance', () => {
    expect(kanbanBoards).toBeInstanceOf(ApiClient);
    expect(kanbanBoards).toHaveProperty('get');
    expect(kanbanBoards).toHaveProperty('show');
    expect(kanbanBoards).toHaveProperty('create');
    expect(kanbanBoards).toHaveProperty('update');
    expect(kanbanBoards).toHaveProperty('delete');
  });
});
