require 'rails_helper'

RSpec.describe KanbanCardPolicy, type: :policy do
  subject(:kanban_card_policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator_context) { { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }

  let(:board) { create(:kanban_board, account: account) }
  let(:stage) { create(:kanban_stage, account: account, kanban_board: board) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact, inbox: inbox) }
  let(:manual_card) do
    create(:kanban_card, account: account, kanban_board: board, kanban_stage: stage, contact: contact, inbox: inbox)
  end
  let(:conversation_card) do
    create(:kanban_card, :conversation_origin, conversation: conversation, kanban_board: board, kanban_stage: stage)
  end

  permissions :show?, :create?, :update?, :destroy?, :reorder? do
    context 'when card is conversation-backed' do
      context 'when user is an administrator' do
        it 'allows access to a valid card' do
          expect(kanban_card_policy).to permit(administrator_context, conversation_card)
        end
      end

      context 'when user can view the conversation through ConversationPolicy' do
        let(:team) { create(:team, account: account) }
        let(:conversation) { create(:conversation, :with_team, account: account, contact: contact, inbox: inbox, team: team) }

        before { create(:team_member, team: team, user: agent) }

        it 'allows access' do
          expect(kanban_card_policy).to permit(agent_context, conversation_card)
        end
      end

      context 'when user cannot view the conversation through ConversationPolicy' do
        it 'denies access' do
          expect(kanban_card_policy).not_to permit(agent_context, conversation_card)
        end
      end
    end

    context 'when card is manual' do
      context 'when user is an administrator' do
        it 'allows access to a valid card' do
          expect(kanban_card_policy).to permit(administrator_context, manual_card)
        end
      end

      context 'when agent has inbox access' do
        before { create(:inbox_member, user: agent, inbox: inbox) }

        it 'allows access to a valid card' do
          expect(kanban_card_policy).to permit(agent_context, manual_card)
        end
      end

      context 'when agent lacks inbox access' do
        it 'denies access' do
          expect(kanban_card_policy).not_to permit(agent_context, manual_card)
        end
      end
    end

    context 'when the board is inactive' do
      before { board.update!(active: false) }

      it 'denies access' do
        expect(kanban_card_policy).not_to permit(administrator_context, manual_card)
      end
    end

    context 'when the stage is inactive' do
      before { stage.update!(active: false) }

      it 'denies access' do
        expect(kanban_card_policy).not_to permit(administrator_context, manual_card)
      end
    end
  end

  permissions :show? do
    context 'when card belongs to another account' do
      let(:other_account) { create(:account) }
      let(:card) do
        build(:kanban_card, account: other_account, kanban_board: board, kanban_stage: stage, contact: contact, inbox: inbox)
      end

      it 'denies access' do
        expect(kanban_card_policy).not_to permit(administrator_context, card)
      end
    end

    context 'when board belongs to another account' do
      it 'denies access' do
        other_board = create(:kanban_board)
        other_stage = create(:kanban_stage, account: other_board.account, kanban_board: other_board)
        card = build(:kanban_card, account: account, kanban_board: other_board, kanban_stage: other_stage, contact: contact, inbox: inbox)

        expect(kanban_card_policy).not_to permit(administrator_context, card)
      end
    end

    context 'when stage belongs to another board' do
      it 'denies access' do
        other_board = create(:kanban_board, account: account)
        other_stage = create(:kanban_stage, account: account, kanban_board: other_board)
        card = build(:kanban_card, account: account, kanban_board: board, kanban_stage: other_stage, contact: contact, inbox: inbox)

        expect(kanban_card_policy).not_to permit(administrator_context, card)
      end
    end

    context 'when stage belongs to another account' do
      let(:other_stage) { create(:kanban_stage) }
      let(:card) do
        build(:kanban_card, account: account, kanban_board: board, kanban_stage: other_stage, contact: contact, inbox: inbox)
      end

      it 'denies access' do
        expect(kanban_card_policy).not_to permit(administrator_context, card)
      end
    end

    context 'when contact belongs to another account' do
      let(:other_contact) { create(:contact) }
      let(:card) do
        build(:kanban_card, account: account, kanban_board: board, kanban_stage: stage, contact: other_contact, inbox: inbox)
      end

      it 'denies access' do
        expect(kanban_card_policy).not_to permit(administrator_context, card)
      end
    end

    context 'when inbox belongs to another account' do
      let(:other_inbox) { create(:inbox) }
      let(:card) do
        build(:kanban_card, account: account, kanban_board: board, kanban_stage: stage, contact: contact, inbox: other_inbox)
      end

      it 'denies access' do
        expect(kanban_card_policy).not_to permit(administrator_context, card)
      end
    end

    context 'when conversation belongs to another account' do
      let(:other_conversation) { create(:conversation) }
      let(:card) do
        build(
          :kanban_card,
          :conversation_origin,
          account: account,
          kanban_board: board,
          kanban_stage: stage,
          contact: contact,
          inbox: inbox,
          conversation: other_conversation
        )
      end

      it 'denies access' do
        expect(kanban_card_policy).not_to permit(administrator_context, card)
      end
    end

    context 'when conversation contact does not match card contact' do
      let(:other_contact) { create(:contact, account: account) }
      let(:card) do
        build(
          :kanban_card,
          :conversation_origin,
          account: account,
          kanban_board: board,
          kanban_stage: stage,
          contact: other_contact,
          inbox: inbox,
          conversation: conversation
        )
      end

      it 'denies access' do
        expect(kanban_card_policy).not_to permit(administrator_context, card)
      end
    end

    context 'when conversation inbox does not match card inbox' do
      let(:other_inbox) { create(:inbox, account: account) }
      let(:card) do
        build(
          :kanban_card,
          :conversation_origin,
          account: account,
          kanban_board: board,
          kanban_stage: stage,
          contact: contact,
          inbox: other_inbox,
          conversation: conversation
        )
      end

      it 'denies access' do
        expect(kanban_card_policy).not_to permit(administrator_context, card)
      end
    end
  end
end
