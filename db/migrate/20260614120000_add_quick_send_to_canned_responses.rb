class AddQuickSendToCannedResponses < ActiveRecord::Migration[7.1]
  def change
    add_column :canned_responses, :mode, :string, null: false, default: 'insert'

    create_table :canned_response_steps do |t|
      t.references :canned_response, null: false, foreign_key: true, index: true
      t.string :step_type, null: false, default: 'text'
      t.text :content
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :canned_response_steps, [:canned_response_id, :position]
  end
end
