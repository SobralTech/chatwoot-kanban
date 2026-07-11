require 'rails_helper'
describe ActionCableListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: agent) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    Current.user = nil
    Current.account = nil
  end

  describe '#message_created' do
    let(:event_name) { :'message.created' }
    let!(:message) do
      create(:message, message_type: 'outgoing',
                       account: account, inbox: inbox, conversation: conversation)
    end
    let!(:event) { Events::Base.new(event_name, Time.zone.now, message: message) }

    it 'sends message to account admins, inbox agents and the contact' do
      # HACK: to reload conversation inbox members
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          agent.pubsub_token, admin.pubsub_token, conversation.contact_inbox.pubsub_token
        ),
        'message.created',
        message.push_event_data.merge(account_id: account.id),
        conversation.id
      )
      listener.message_created(event)
    end

    it 'sends message to all hmac verified contact inboxes' do
      # HACK: to reload conversation inbox members
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)
      conversation.contact_inbox.update(hmac_verified: true)
      # creating a non verified contact inbox to ensure the events are not sent to it
      create(:contact_inbox, contact: conversation.contact, inbox: inbox)
      verified_contact_inbox = create(:contact_inbox, contact: conversation.contact, inbox: inbox, hmac_verified: true)

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          agent.pubsub_token, admin.pubsub_token, conversation.contact_inbox.pubsub_token, verified_contact_inbox.pubsub_token
        ),
        'message.created',
        message.push_event_data.merge(account_id: account.id),
        conversation.id
      )
      listener.message_created(event)
    end
  end

  describe '#typing_on' do
    let(:event_name) { :'conversation.typing_on' }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, user: agent, is_private: false) }

    it 'sends message to account admins, inbox agents and the contact' do
      # HACK: to reload conversation inbox members
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          admin.pubsub_token, conversation.contact_inbox.pubsub_token
        ),
        'conversation.typing_on', { conversation: conversation.push_event_data,
                                    user: agent.push_event_data,
                                    account_id: account.id,
                                    is_private: false },
        nil
      )
      listener.conversation_typing_on(event)
    end
  end

  describe '#typing_on with contact' do
    let(:event_name) { :'conversation.typing_on' }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, user: conversation.contact, is_private: false) }

    it 'sends message to account admins, inbox agents and the contact' do
      # HACK: to reload conversation inbox members
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          admin.pubsub_token, agent.pubsub_token
        ),
        'conversation.typing_on', { conversation: conversation.push_event_data,
                                    user: conversation.contact.push_event_data,
                                    account_id: account.id,
                                    is_private: false },
        nil
      )
      listener.conversation_typing_on(event)
    end
  end

  describe '#typing_on with agent bot' do
    let(:event_name) { :'conversation.typing_on' }
    let!(:agent_bot) { create(:agent_bot, account: account) }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, user: agent_bot, is_private: false) }

    it 'sends message to account admins, inbox agents and the contact' do
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          admin.pubsub_token, agent.pubsub_token, conversation.contact_inbox.pubsub_token
        ),
        'conversation.typing_on', { conversation: conversation.push_event_data,
                                    user: agent_bot.push_event_data,
                                    account_id: account.id,
                                    is_private: false },
        nil
      )
      listener.conversation_typing_on(event)
    end
  end

  describe '#typing_off' do
    let(:event_name) { :'conversation.typing_off' }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, user: agent, is_private: false) }

    it 'sends message to account admins, inbox agents and the contact' do
      # HACK: to reload conversation inbox members
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          admin.pubsub_token, conversation.contact_inbox.pubsub_token
        ),
        'conversation.typing_off', { conversation: conversation.push_event_data,
                                     user: agent.push_event_data,
                                     account_id: account.id,
                                     is_private: false },
        nil
      )
      listener.conversation_typing_off(event)
    end
  end

  describe '#contact_deleted' do
    let(:event_name) { :'contact.deleted' }
    let!(:contact) { create(:contact, account: account) }
    let(:contact_data) { contact.push_event_data.merge(account_id: contact.account_id) }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, contact_data: contact_data) }

    it 'sends message to account admins, inbox agents' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        ["account_#{account.id}"],
        'contact.deleted',
        contact_data,
        nil
      )
      listener.contact_deleted(event)
    end
  end

  describe '#notification_deleted' do
    let(:event_name) { :'notification.deleted' }
    let!(:notification) { create(:notification, account: account, user: agent) }
    let(:notification_data) do
      {
        id: notification.id,
        user_id: agent.id,
        account_id: account.id
      }
    end
    let!(:event) { Events::Base.new(event_name, Time.zone.now, notification_data: notification_data) }

    it 'sends message to account admins, inbox agents' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        [agent.pubsub_token],
        'notification.deleted',
        {
          account_id: notification.account_id,
          notification: {
            id: notification.id
          },
          unread_count: 0,
          count: 0
        },
        nil
      )

      listener.notification_deleted(event)
    end
  end

  describe '#notification_updated' do
    let(:event_name) { :'notification.updated' }
    let!(:notification) { create(:notification, account: account, user: agent) }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, notification: notification) }

    it 'sends notification to account admins, inbox agents' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        [agent.pubsub_token],
        'notification.updated',
        {
          account_id: notification.account_id,
          notification: notification.push_event_data,
          unread_count: 0,
          count: 0
        },
        nil
      )

      listener.notification_updated(event)
    end
  end

  describe '#conversation_updated' do
    let(:event_name) { :'conversation.updated' }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, user: agent, is_private: false) }

    before do
      conversation.add_labels(['support'])
    end

    it 'sends update to inbox members' do
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(agent.pubsub_token, admin.pubsub_token, conversation.contact_inbox.pubsub_token),
        'conversation.updated',
        conversation.push_event_data.merge(account_id: account.id),
        conversation.id
      )
      listener.conversation_updated(event)
    end

    it 'broadcast event with label data' do
      expect(conversation.reload.push_event_data[:labels]).to eq(conversation.labels.pluck(:name))

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(agent.pubsub_token, admin.pubsub_token, conversation.contact_inbox.pubsub_token),
        'conversation.updated',
        conversation.push_event_data.merge(account_id: account.id),
        conversation.id
      )
      listener.conversation_updated(event)
    end
  end

  describe '#conversation_unread_count_changed' do
    let(:event_name) { :'conversation.unread_count_changed' }
    let!(:agent_without_inbox_access) { create(:user, account: account, role: :agent) }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation) }

    before do
      account.enable_features!(:conversation_unread_counts)
    end

    it 'sends a lightweight refresh event to inbox agents and admins' do
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(agent.pubsub_token, admin.pubsub_token),
        'conversation.unread_count_changed',
        {
          account_id: account.id
        },
        nil
      )

      listener.conversation_unread_count_changed(event)
    end

    it 'does not broadcast unread count refresh to agents outside the inbox' do
      expect(ActionCableBroadcastJob).not_to receive(:perform_later).with(
        array_including(agent_without_inbox_access.pubsub_token),
        anything,
        anything
      )

      listener.conversation_unread_count_changed(event)
    end

    it 'does not broadcast when conversation unread counts feature is disabled' do
      account.disable_features!(:conversation_unread_counts)

      expect(ActionCableBroadcastJob).not_to receive(:perform_later)

      listener.conversation_unread_count_changed(event)
    end

    it 'supports deleted conversation data' do
      event = Events::Base.new(
        event_name,
        Time.zone.now,
        conversation_data: {
          id: conversation.id,
          account_id: account.id,
          inbox_id: conversation.inbox_id
        }
      )

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(agent.pubsub_token, admin.pubsub_token),
        'conversation.unread_count_changed',
        {
          account_id: account.id
        },
        nil
      )

      listener.conversation_unread_count_changed(event)
    end
  end

  describe '#conversation_access_revoked' do
    let(:event_name) { :'conversation.access_revoked' }
    let(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, tokens: [agent.pubsub_token]) }

    it 'enqueues a compact payload for revoked users' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        [agent.pubsub_token],
        'conversation.access_revoked',
        { account_id: account.id, id: conversation.display_id },
        nil
      )

      listener.conversation_access_revoked(event)
    end
  end

  describe '#kanban events' do
    let(:board_payload) { { account_id: account.id, board_id: 10 } }
    let(:stage_payload) { board_payload.merge(stage_id: 20) }
    let(:card_payload) { stage_payload.merge(card_id: 30, conversation_id: 40) }
    let(:manual_card_payload) { stage_payload.merge(card_id: 30, conversation_id: nil) }
    let(:card_reorder_payload) { board_payload.merge(card_id: 30, conversation_id: 40, source_stage_id: 20, target_stage_id: 21) }

    it 'enqueues kanban.board.updated to the account stream with compact payload' do
      expect_kanban_broadcast(:kanban_board_updated, Events::Types::KANBAN_BOARD_UPDATED, board_payload, %i[account_id board_id])
    end

    it 'enqueues kanban.stage.created to the account stream with compact payload' do
      expect_kanban_broadcast(:kanban_stage_created, Events::Types::KANBAN_STAGE_CREATED, stage_payload, %i[account_id board_id stage_id])
    end

    it 'enqueues kanban.stage.updated to the account stream with compact payload' do
      expect_kanban_broadcast(:kanban_stage_updated, Events::Types::KANBAN_STAGE_UPDATED, stage_payload, %i[account_id board_id stage_id])
    end

    it 'enqueues kanban.stage.deleted to the account stream with compact payload' do
      expect_kanban_broadcast(:kanban_stage_deleted, Events::Types::KANBAN_STAGE_DELETED, stage_payload, %i[account_id board_id stage_id])
    end

    it 'enqueues kanban.stage.reordered to the account stream with compact payload' do
      expect_kanban_broadcast(:kanban_stage_reordered, Events::Types::KANBAN_STAGE_REORDERED, stage_payload, %i[account_id board_id stage_id])
    end

    it 'enqueues kanban.card.created to the account stream with compact payload' do
      expect_kanban_broadcast(
        :kanban_card_created,
        Events::Types::KANBAN_CARD_CREATED,
        card_payload,
        %i[account_id board_id stage_id card_id conversation_id]
      )
    end

    it 'enqueues kanban.card.updated to the account stream with compact payload' do
      expect_kanban_broadcast(
        :kanban_card_updated,
        Events::Types::KANBAN_CARD_UPDATED,
        card_payload,
        %i[account_id board_id stage_id card_id conversation_id]
      )
    end

    it 'enqueues kanban.card.deleted to the account stream with compact payload' do
      expect_kanban_broadcast(
        :kanban_card_deleted,
        Events::Types::KANBAN_CARD_DELETED,
        card_payload,
        %i[account_id board_id stage_id card_id conversation_id]
      )
    end

    it 'enqueues kanban.card.created with nil conversation_id for manual cards without conversation' do
      expect_kanban_broadcast(
        :kanban_card_created,
        Events::Types::KANBAN_CARD_CREATED,
        manual_card_payload,
        %i[account_id board_id stage_id card_id conversation_id]
      )
    end

    it 'enqueues kanban.card.reordered to the account stream with source and target stage IDs' do
      expect_kanban_broadcast(
        :kanban_card_reordered,
        Events::Types::KANBAN_CARD_REORDERED,
        card_reorder_payload,
        %i[account_id board_id card_id conversation_id source_stage_id target_stage_id]
      )
    end
  end

  def expect_kanban_broadcast(method_name, event_name, payload, expected_keys)
    expect(payload.keys).to match_array(expected_keys)
    expect(payload).not_to include(:contact, :inbox, :conversation, :card)
    expect(ActionCableBroadcastJob).to receive(:perform_later).with(["account_#{account.id}"], event_name, payload)

    listener.public_send(method_name, Events::Base.new(event_name, Time.zone.now, payload))
  end
end
