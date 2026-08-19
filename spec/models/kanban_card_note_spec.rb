require 'rails_helper'

RSpec.describe KanbanCardNote do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:card) { create(:kanban_card, account: account) }
  let(:note) { build(:kanban_card_note, account: account, kanban_card: card, user: user) }

  describe 'validations' do
    it 'requires content' do
      note.content = nil

      expect(note).not_to be_valid
      expect(note.errors[:content]).to include("can't be blank")
    end

    it 'limits content to 10,000 characters' do
      note.content = 'a' * 10_001

      expect(note).not_to be_valid
      expect(note.errors[:content].join).to include('too long')
    end

    it 'requires the card to belong to the same account' do
      note.kanban_card = create(:kanban_card, account: create(:account))

      expect(note).not_to be_valid
      expect(note.errors[:kanban_card]).to include('is invalid')
    end

    it 'limits the number of attachments' do
      note.attachments.attach(
        Array.new(6) do |index|
          { io: StringIO.new("file #{index}"), filename: "file-#{index}.txt", content_type: 'text/plain' }
        end
      )

      expect(note).not_to be_valid
      expect(note.errors[:attachments]).to include('Up to 5 files per note.')
    end

    it 'limits each attachment to 20MB' do
      Tempfile.create('large-kanban-note') do |file|
        file.truncate(KanbanCardNote::MAX_ATTACHMENT_SIZE + 1)
        file.rewind
        note.attachments.attach(io: file, filename: 'large.txt', content_type: 'text/plain')

        expect(note).not_to be_valid
        expect(note.errors[:attachments]).to include('Each file must be 20MB or smaller.')
      end
    end
  end

  describe 'card deletion' do
    it 'deletes notes and their active storage attachments with the card' do
      note.save!
      note.attachments.attach(
        io: Rails.root.join('spec/assets/avatar.png').open,
        filename: 'avatar.png',
        content_type: 'image/png'
      )
      blob = note.attachments.first.blob

      perform_enqueued_jobs { card.destroy! }

      expect(described_class.exists?(note.id)).to be(false)
      expect(ActiveStorage::Attachment.exists?(record: note)).to be(false)
      expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
    end
  end
end
