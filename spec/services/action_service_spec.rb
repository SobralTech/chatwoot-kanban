require 'rails_helper'

describe ActionService do
  let(:account) { create(:account) }

  describe '#resolve_conversation' do
    let(:conversation) { create(:conversation) }
    let(:action_service) { described_class.new(conversation) }

    it 'resolves the conversation' do
      expect(conversation.status).to eq('open')
      action_service.resolve_conversation(nil)
      expect(conversation.reload.status).to eq('resolved')
    end
  end

  describe '#open_conversation' do
    let(:conversation) { create(:conversation, status: :resolved) }
    let(:action_service) { described_class.new(conversation) }

    it 'opens the conversation' do
      expect(conversation.status).to eq('resolved')
      action_service.open_conversation(nil)
      expect(conversation.reload.status).to eq('open')
    end
  end

  describe '#change_priority' do
    let(:conversation) { create(:conversation) }
    let(:action_service) { described_class.new(conversation) }

    it 'changes the priority of the conversation to medium' do
      action_service.change_priority(['medium'])
      expect(conversation.reload.priority).to eq('medium')
    end

    it 'changes the priority of the conversation to nil' do
      action_service.change_priority(['nil'])
      expect(conversation.reload.priority).to be_nil
    end
  end

  describe '#assign_agent' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:inbox_member) { create(:inbox_member, inbox: conversation.inbox, user: agent) }
    let(:conversation) { create(:conversation, :with_assignee, account: account) }
    let(:action_service) { described_class.new(conversation) }

    it 'unassigns the conversation if agent id is nil' do
      action_service.assign_agent(['nil'])
      expect(conversation.reload.assignee).to be_nil
    end

    context 'when agent is confirmed' do
      it 'assigns the agent to the conversation' do
        inbox_member
        action_service.assign_agent([agent.id])
        expect(conversation.reload.assignee).to eq(agent)
      end
    end

    context 'when agent is unconfirmed' do
      let(:unconfirmed_agent) { create(:user, account: account, role: :agent, skip_confirmation: false) }
      let(:unconfirmed_inbox_member) { create(:inbox_member, inbox: conversation.inbox, user: unconfirmed_agent) }

      it 'does not assign unconfirmed agent to the conversation' do
        unconfirmed_inbox_member
        original_assignee = conversation.assignee
        action_service.assign_agent([unconfirmed_agent.id])
        expect(conversation.reload.assignee).to eq(original_assignee)
      end
    end

    context 'when assigning the last responding agent' do
      it 'assigns the last agent who replied publicly' do
        note_author = create(:user, account: account, role: :agent)
        inbox_member
        create(:inbox_member, inbox: conversation.inbox, user: note_author)
        create(:message, message_type: :outgoing, account: account,
                         inbox: conversation.inbox, conversation: conversation, sender: agent)
        create(:message, message_type: :outgoing, private: true, account: account,
                         inbox: conversation.inbox, conversation: conversation, sender: note_author)

        action_service.assign_agent(['last_responding_agent'])

        expect(conversation.reload.assignee).to eq(agent)
      end

      it 'does not assign the conversation when there is no public agent reply' do
        inbox_member
        original_assignee = conversation.assignee
        create(:message, message_type: :outgoing, private: true, account: account,
                         inbox: conversation.inbox, conversation: conversation, sender: agent)

        action_service.assign_agent(['last_responding_agent'])

        expect(conversation.reload.assignee).to eq(original_assignee)
      end
    end
  end

  describe '#assign_team' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:inbox_member) { create(:inbox_member, inbox: conversation.inbox, user: agent) }
    let(:team) { create(:team, name: 'ConversationTeam', account: account) }
    let(:conversation) { create(:conversation, :with_team, account: account) }
    let(:action_service) { described_class.new(conversation) }

    context 'when team_id is not present' do
      it 'unassign the if team_id is "nil"' do
        expect do
          action_service.assign_team(['nil'])
        end.not_to raise_error
        expect(conversation.reload.team).to be_nil
      end

      it 'unassign the if team_id is 0' do
        expect do
          action_service.assign_team([0])
        end.not_to raise_error
        expect(conversation.reload.team).to be_nil
      end
    end

    context 'when team_id is present' do
      it 'assign the team if the team is part of the account' do
        original_team = conversation.team
        expect do
          action_service.assign_team([team.id])
        end.to change { conversation.reload.team }.from(original_team)
      end

      it 'does not assign the team if the team is part of the account' do
        original_team = conversation.team
        invalid_team_id = 999_999_999
        expect do
          action_service.assign_team([invalid_team_id])
        end.not_to change { conversation.reload.team }.from(original_team)
      end
    end
  end

  describe '#remove_assigned_agent' do
    let(:conversation) { create(:conversation, :with_assignee, account: account) }
    let(:action_service) { described_class.new(conversation) }

    it 'unassigns the conversation' do
      expect(conversation.reload.assignee).to be_present
      action_service.remove_assigned_agent(nil)
      expect(conversation.reload.assignee).to be_nil
    end
  end

  describe '#add_to_kanban_board' do
    let(:conversation) { create(:conversation, account: account) }
    let(:kanban_board) { create(:kanban_board, account: account) }
    let(:kanban_stage) { create(:kanban_stage, account: account, kanban_board: kanban_board) }
    let(:action_service) { described_class.new(conversation) }
    let(:params) { [{ kanban_board_id: kanban_board.id, kanban_stage_id: kanban_stage.id }] }

    it 'creates a conversation card in the selected stage' do
      action_service.add_to_kanban_board(params)

      expect(KanbanCard.conversation.find_by(conversation: conversation)).to have_attributes(
        kanban_board_id: kanban_board.id,
        kanban_stage_id: kanban_stage.id
      )
    end

    it 'does not create a duplicate when the action runs twice' do
      action_service.add_to_kanban_board(params)

      expect { action_service.add_to_kanban_board(params) }.not_to change(KanbanCard, :count)
    end

    it 'skips a conversation outside the board inbox scope' do
      kanban_board.update!(inbox_scope_mode: 'selected_inboxes')

      expect { action_service.add_to_kanban_board(params) }.not_to change(KanbanCard, :count)
    end
  end

  describe '#move_kanban_card' do
    let(:conversation) { create(:conversation, account: account) }
    let(:kanban_board) { create(:kanban_board, account: account) }
    let(:source_stage) { create(:kanban_stage, account: account, kanban_board: kanban_board, position: 1) }
    let(:target_stage) { create(:kanban_stage, account: account, kanban_board: kanban_board, position: 2) }
    let!(:card) do
      create(:kanban_card, :conversation_origin, conversation: conversation, kanban_board: kanban_board,
                                                 kanban_stage: source_stage, position: 1)
    end
    let(:action_service) { described_class.new(conversation) }

    it 'moves the active conversation card to the selected stage' do
      action_service.move_kanban_card([{ kanban_board_id: kanban_board.id, kanban_stage_id: target_stage.id }])

      expect(card.reload.kanban_stage_id).to eq(target_stage.id)
    end

    it 'does not move a card to the won stage' do
      won_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 3)
      kanban_board.update!(won_stage_id: won_stage.id)

      action_service.move_kanban_card([{ kanban_board_id: kanban_board.id, kanban_stage_id: won_stage.id }])

      expect(card.reload.kanban_stage_id).to eq(source_stage.id)
    end
  end

  describe '#assign_kanban_card' do
    let(:conversation) { create(:conversation, account: account) }
    let(:kanban_board) { create(:kanban_board, account: account) }
    let(:kanban_stage) { create(:kanban_stage, account: account, kanban_board: kanban_board) }
    let(:agent) { create(:user, account: account, role: :agent) }
    let!(:card) do
      create(:kanban_card, :conversation_origin, conversation: conversation, kanban_board: kanban_board,
                                                 kanban_stage: kanban_stage, position: 1)
    end
    let(:action_service) { described_class.new(conversation) }

    it 'assigns the selected agents to the active conversation card' do
      action_service.assign_kanban_card([
                                          { kanban_board_id: kanban_board.id, agent_ids: [agent.id] }
                                        ])

      expect(card.reload.assignees).to contain_exactly(agent)
    end
  end
end
