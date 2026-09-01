require 'rails_helper'

RSpec.describe KanbanBoard do
  describe 'defaults' do
    it 'disables automatic card creation for new boards' do
      board = described_class.new

      expect(board.auto_create_cards_from_conversations).to be(false)
    end

    it 'disables contact recurrence for new boards' do
      board = described_class.new

      expect(board.won_recurrence_enabled).to be(false)
      expect(board.lost_recurrence_enabled).to be(false)
    end

    it 'keeps new boards visible to all agents' do
      board = described_class.new

      expect(board.visibility_mode).to eq('all_agents')
    end

    it 'keeps persisted boards visible to all agents when visibility is not specified' do
      board = create(:kanban_board)

      expect(board.visibility_mode).to eq('all_agents')
    end
  end

  describe 'validations' do
    it 'prevents duplicate active names inside an account' do
      account = create(:account)
      create(:kanban_board, account: account, name: 'Sales')

      board = build(:kanban_board, account: account, name: 'Sales')

      expect(board).not_to be_valid
      expect(board.errors[:name]).to be_present
    end

    it 'allows the same name when the previous board is inactive' do
      account = create(:account)
      create(:kanban_board, account: account, name: 'Sales', active: false)

      board = build(:kanban_board, account: account, name: 'Sales')

      expect(board).to be_valid
    end

    it 'allows the same name in another account' do
      create(:kanban_board, account: create(:account), name: 'Sales')
      other_account = create(:account)

      board = build(:kanban_board, account: other_account, name: 'Sales')

      expect(board).to be_valid
    end

    it 'accepts supported visibility modes' do
      account = create(:account)

      described_class::VISIBILITY_MODES.each do |visibility_mode|
        board = build(:kanban_board, account: account, visibility_mode: visibility_mode)

        expect(board).to be_valid
      end
    end

    it 'rejects unsupported visibility modes' do
      board = build(:kanban_board, account: create(:account), visibility_mode: 'private')

      expect(board).not_to be_valid
      expect(board.errors[:visibility_mode]).to be_present
    end

    it 'defaults to all_inboxes inbox scope' do
      board = described_class.new

      expect(board.inbox_scope_mode).to eq('all_inboxes')
    end

    it 'persists all_inboxes as default inbox scope' do
      board = create(:kanban_board)

      expect(board.inbox_scope_mode).to eq('all_inboxes')
    end

    it 'accepts supported inbox scope modes' do
      account = create(:account)

      described_class::INBOX_SCOPE_MODES.each do |mode|
        board = build(:kanban_board, account: account, inbox_scope_mode: mode)

        expect(board).to be_valid
      end
    end

    it 'rejects unsupported inbox scope modes' do
      board = build(:kanban_board, account: create(:account), inbox_scope_mode: 'restricted')

      expect(board).not_to be_valid
      expect(board.errors[:inbox_scope_mode]).to be_present
    end

    it 'requires the won recurrence window when recurrence is enabled' do
      board = build(:kanban_board, won_recurrence_enabled: true)

      expect(board).not_to be_valid
      expect(board.errors[:won_recurrence_window_minutes]).to be_present
    end

    it 'requires the lost recurrence window when recurrence is enabled' do
      board = build(:kanban_board, lost_recurrence_enabled: true)

      expect(board).not_to be_valid
      expect(board.errors[:lost_recurrence_window_minutes]).to be_present
    end

    it 'allows recurrence to remain disabled without a window' do
      board = build(:kanban_board, account: create(:account), won_recurrence_enabled: false, lost_recurrence_enabled: false)

      expect(board).to be_valid
    end
  end

  describe 'associations' do
    it 'exposes board members as visible users' do
      board = create(:kanban_board)
      user = create(:user, account: board.account)
      create(:kanban_board_member, account: board.account, kanban_board: board, user: user)

      expect(board.kanban_board_members.count).to eq(1)
      expect(board.visible_users).to contain_exactly(user)
    end

    it 'exposes the inboxes its entry rules name' do
      board = create(:kanban_board)
      inbox = create(:inbox, account: board.account)
      restrict_board_to(board, inbox)

      expect(board.kanban_board_entry_rule_inboxes.count).to eq(1)
      expect(board.derived_allowed_inbox_ids).to contain_exactly(inbox.id)
    end
  end

  describe '#inbox_allowed?' do
    let(:account) { create(:account) }
    let(:board) { create(:kanban_board, account: account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:other_account_inbox) { create(:inbox) }

    it 'accepts any account inbox when no rule narrows the board' do
      expect(board).to be_derived_all_inboxes

      expect(board.inbox_allowed?(inbox)).to be(true)
    end

    it 'accepts inbox by id when no rule narrows the board' do
      expect(board.inbox_allowed?(inbox.id)).to be(true)
    end

    it 'rejects inbox from another account' do
      expect(board.inbox_allowed?(other_account_inbox)).to be(false)
    end

    it 'accepts any account inbox when an active rule covers all inboxes' do
      create(:kanban_board_entry_rule, account: account, kanban_board: board)

      expect(board.inbox_allowed?(inbox)).to be(true)
    end

    it 'accepts an inbox its active rule names' do
      restrict_board_to(board, inbox)

      expect(board.inbox_allowed?(inbox)).to be(true)
    end

    it 'rejects an inbox no active rule names' do
      restrict_board_to(board)

      expect(board.inbox_allowed?(inbox)).to be(false)
      expect(board.inbox_allowed?(other_account_inbox)).to be(false)
    end

    it 'ignores the inboxes of an inactive rule' do
      restrict_board_to(board, inbox).update!(active: false)

      expect(board.inbox_allowed?(inbox)).to be(true)
    end

    it 'returns false for nil or blank' do
      expect(board.inbox_allowed?(nil)).to be(false)
      expect(board.inbox_allowed?('')).to be(false)
    end
  end

  describe 'scope .accepting_inbox' do
    it 'includes boards with no active entry rule' do
      board = create(:kanban_board)
      inbox = create(:inbox, account: board.account)

      expect(described_class.accepting_inbox(inbox.id)).to include(board)
    end

    it 'includes boards whose active rule covers all inboxes' do
      board = create(:kanban_board)
      inbox = create(:inbox, account: board.account)
      create(:kanban_board_entry_rule, account: board.account, kanban_board: board)

      expect(described_class.accepting_inbox(inbox.id)).to include(board)
    end

    it 'includes boards whose active rule names the inbox' do
      board = create(:kanban_board)
      inbox = create(:inbox, account: board.account)
      restrict_board_to(board, inbox)

      expect(described_class.accepting_inbox(inbox.id)).to include(board)
    end

    it 'excludes boards whose active rule does not name the inbox' do
      board = create(:kanban_board)
      inbox = create(:inbox, account: board.account)
      restrict_board_to(board, create(:inbox, account: board.account))

      expect(described_class.accepting_inbox(inbox.id)).not_to include(board)
    end

    it 'excludes boards when the inbox belongs to another account' do
      board = create(:kanban_board)
      restrict_board_to(board, create(:inbox, account: board.account))
      inbox = create(:inbox, account: create(:account))

      expect(described_class.accepting_inbox(inbox.id)).not_to include(board)
    end
  end

  def restrict_board_to(board, *inboxes)
    rule = create(:kanban_board_entry_rule, :selected_inboxes, account: board.account, kanban_board: board)
    inboxes.each do |inbox|
      create(:kanban_board_entry_rule_inbox, account: board.account, kanban_board_entry_rule: rule, inbox: inbox)
    end
    rule
  end
end
