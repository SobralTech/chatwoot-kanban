class AddTypingSimulationEnabledToChannelWaha < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_waha, :typing_simulation_enabled, :boolean, default: true, null: false
  end
end
