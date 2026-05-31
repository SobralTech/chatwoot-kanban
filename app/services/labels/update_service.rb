class Labels::UpdateService
  pattr_initialize [:new_label_title!, :old_label_title!, :account_id!]

  def perform
    update_tagged_records(tagged_conversations)
    update_tagged_records(tagged_contacts)
    update_tagged_records(tagged_kanban_cards)
  end

  private

  def update_tagged_records(records)
    records.find_in_batches do |record_batch|
      record_batch.each do |record|
        record.label_list.remove(old_label_title)
        record.label_list.add(new_label_title)
        record.save!
      end
    end
  end

  def tagged_conversations
    account.conversations.tagged_with(old_label_title)
  end

  def tagged_contacts
    account.contacts.tagged_with(old_label_title)
  end

  def tagged_kanban_cards
    KanbanCard.where(account_id: account.id).tagged_with(old_label_title)
  end

  def account
    @account ||= Account.find(account_id)
  end
end
