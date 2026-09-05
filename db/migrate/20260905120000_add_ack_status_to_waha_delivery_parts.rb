class AddAckStatusToWahaDeliveryParts < ActiveRecord::Migration[7.1]
  # Each part of a multipart message gets its own WhatsApp delivery receipt.
  # Keeping them apart is what lets the aggregate Chatwoot status be the weakest
  # state across the parts instead of whichever part acked last.
  def change
    add_column :waha_delivery_parts, :ack_status, :integer
  end
end
