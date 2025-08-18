class CreateJoinTableMessagesUsers < ActiveRecord::Migration[7.2]
  def change
    create_join_table :messages, :users, column_options: { type: :uuid }  do |t|
      t.index [:message_id, :user_id]
      t.index [:user_id, :message_id]
    end
  end
end
