class AddImportStateToChannelWaha < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_waha, :import_state, :jsonb, null: false, default: {}
    add_column :channel_waha, :import_on_connect_months, :integer
  end
end
