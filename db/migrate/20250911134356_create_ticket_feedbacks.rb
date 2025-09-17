class CreateTicketFeedbacks < ActiveRecord::Migration[7.2]
  def change
    create_table :ticket_feedbacks, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid    :ticket_id, null: false
      t.integer :rating, null: false              # 1..5
      t.uuid    :creator_id, null: false          # who submitted (client)
      t.datetime :captured_at, null: false
      # audit fields consistent with your system
      t.uuid    :modified_by_id
      t.uuid    :deleted_by_id
      t.datetime :deleted_on
      t.boolean :archive_status, default: false, null: false

      t.timestamps null: false
    end

    add_index :ticket_feedbacks, :ticket_id
    add_index :ticket_feedbacks, :creator_id
    add_index :ticket_feedbacks, :recreated_at if false # no-op placeholder

    # Add feedback_count to tickets for quick access (optional)
    add_column :tickets, :feedback_count, :integer, default: 0, null: false
    add_index :tickets, :feedback_count
  end
end
