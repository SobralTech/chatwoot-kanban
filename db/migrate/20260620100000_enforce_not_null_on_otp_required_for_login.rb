class EnforceNotNullOnOtpRequiredForLogin < ActiveRecord::Migration[7.1]
  def up
    execute 'UPDATE users SET otp_required_for_login = false WHERE otp_required_for_login IS NULL'
    change_column_null :users, :otp_required_for_login, false
  end

  def down
    change_column_null :users, :otp_required_for_login, true
  end
end
