class EnforceDefaultAndNotNullOnCompaniesContactsCount < ActiveRecord::Migration[7.1]
  def up
    execute 'UPDATE companies SET contacts_count = 0 WHERE contacts_count IS NULL'
    change_column_default :companies, :contacts_count, 0
    change_column_null :companies, :contacts_count, false
  end

  def down
    change_column_null :companies, :contacts_count, true
    change_column_default :companies, :contacts_count, nil
  end
end
