class CreateWebhookEvents < ActiveRecord::Migration[6.1]
  def change
    create_table :webhook_events do |t|
      t.integer :webhook_endpoint_id, null: false, index: true 

      t.string :event, null: false 
      t.text :payload, null: false

      t.timestamps null: false
    end
  end
end
