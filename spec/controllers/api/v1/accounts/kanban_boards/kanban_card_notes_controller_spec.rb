require 'rails_helper'

RSpec.describe 'Kanban card notes API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:kanban_board) { create(:kanban_board, account: account) }
  let(:stage) { create(:kanban_stage, account: account, kanban_board: kanban_board) }
  let(:inbox) { create(:inbox, account: account) }
  let(:card) do
    create(
      :kanban_card,
      account: account,
      kanban_board: kanban_board,
      kanban_stage: stage,
      inbox: inbox
    )
  end

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    create(:inbox_member, user: other_agent, inbox: inbox)
  end

  it 'creates a note with an attachment' do
    file = fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')

    post notes_url,
         params: { note: { content: 'Quote sent by email.', attachments: [file] } },
         headers: agent.create_new_auth_token

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('content' => 'Quote sent by email.')
    expect(response.parsed_body['attachments']).to include(
      include(
        'filename' => 'avatar.png',
        'content_type' => 'image/png',
        'byte_size' => file.size
      )
    )
    expect(card.kanban_card_notes.last.user).to eq(agent)
  end

  it 'updates a note created by the current agent' do
    note = create(:kanban_card_note, account: account, kanban_card: card, user: agent)

    patch note_url(note),
          params: { note: { content: 'Updated follow-up.' } },
          headers: agent.create_new_auth_token,
          as: :json

    expect(response).to have_http_status(:success)
    expect(note.reload.content).to eq('Updated follow-up.')
  end

  it 'does not let an agent delete another agent\'s note' do
    note = create(:kanban_card_note, account: account, kanban_card: card, user: other_agent)

    delete note_url(note), headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(KanbanCardNote.exists?(note.id)).to be(true)
  end

  it 'lets an administrator delete another agent\'s note' do
    note = create(:kanban_card_note, account: account, kanban_card: card, user: other_agent)

    delete note_url(note), headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:no_content)
    expect(KanbanCardNote.exists?(note.id)).to be(false)
  end

  private

  def notes_url
    "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}/notes"
  end

  def note_url(note)
    "#{notes_url}/#{note.id}"
  end
end
