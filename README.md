# WEBHOOK TUTORIAL
This guide is mostly written base on the reference from keygen:
"https://keygen.sh/blog/how-to-build-a-webhook-system-in-rails-using-sidekiq/".

A quick introduction for how to define our webhook resources here.
In noob words, when some event happen, we want to notify all subscribers. An event here take it quite literally, i.e. "a successful payment", "a user updated his profile" etc. A subscriber are "people" who want to get notified when these thing happen. So, whenever the event trigger, subscriber will get "NOTIFIED".

## GETTING STARTED
```
$ rails new webhook101 --api --database postgresql --skip-active-storage --skip-action-cable
```

### Migration
We create our first table, "A WEBHOOK ENDPONT". These are going to represent the "subscribers" in our webhook system.
```
$ rails g migration CreateWebhookEndpoints
```
and for the migration file
```ruby
class CreateWebhookEndpoints < ActiveRecord::Migration[5.2]
  def change
    create_table :webhook_endpoints do |t|
      t.string :url, null: false

      t.timestamps null: false
    end
  end
end
```

Now we create another table for "WEBHOOK EVENT". As the name implies, these will represent the "events" in our webhook system.
```
$ rails g mgiration CreateWebhookEvents 
```

Then let's define the schema for the event
```ruby
class CreateWebhookEvents < ActiveRecord::Migration[5.2]
  def change
    create_table :webhook_events do |t|
      t.integer :webhook_endpoint_id, null: false, index: true

      t.string :event, null: false
      t.text :payload, null: false

      t.timestamps null: false
    end
  end
end
```
and run "db:migrate".

### Models 
Now we setup the models for the webhooks. One for each of the migrations that we have just created.
```ruby 
class WebhookEndpoint < ApplicationRecord
  has_many :webhook_events, inverse_of: :webhook_endpoint

  validates :url, presence: true
end

class WebhookEvent < ApplicationRecord
  belongs_to :webhook_endpoint, inverse_of: :webhook_events

  validates :event, presence: true
  validates :payload, presence: true
end
```
Now we are ready for a first test in the console..

```
$ rails c
> WebhookEndpoint.create!(url: 'https://functions.ecorp.example/webhooks')
# => #<WebhookEndpoint
#       id: 1,
#       url: "https://functions.ecorp.example/webhooks",
#       created_at: "2021-06-14 22:14:53.587473000 +0000",
#       updated_at: "2021-06-14 22:14:53.587473000 +0000"
#     >
> WebhookEvent.create!(
    webhook_endpoint: _,
    event: 'events.test',
    payload: { test: 1 }
  )
# => #<WebhookEvent
#       id: 1,
#       webhook_endpoint_id: 1,
#       event: "events.test",
#       payload: { "test" => 1 },
#       created_at: "2021-06-14 22:17:06.908392000 +0000",
#       updated_at: "2021-06-14 22:17:06.908392000 +0000"
#     >
```

