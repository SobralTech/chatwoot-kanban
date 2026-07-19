class AddSigningAndNumberLockToChannelWaha < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_waha, :signing_enabled, :boolean, default: false, null: false
    add_column :channel_waha, :connected_number_locked, :boolean, default: false, null: false
  end
end
