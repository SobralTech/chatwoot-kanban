require 'rails_helper'

describe Waha::HistoryMediaDispatchJob do
  it 'starts deferred media only after textual convergence is terminal' do
    channel = create(:channel_waha)
    execution_id = SecureRandom.uuid
    message = create_waha_message(account: channel.account, inbox: channel.inbox, source_id: 'MEDIA1')
    channel.import_chats.create!(chat_id: 'chat@c.us', media_message_ids: [message.id])
    channel.update_import_state!(
      'status' => 'completed', 'phase' => 'completed', 'kind' => 'initial',
      'execution_id' => execution_id, 'media_pending' => true
    )

    expect { described_class.perform_now(channel.id, execution_id) }
      .to have_enqueued_job(Waha::HistoryMediaJob).with(channel.id, 'chat@c.us', [message.id])

    expect(channel.reload.import_state).to include('media_pending' => false)
  end
end
