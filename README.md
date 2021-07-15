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

## Building webhook workers
We start by adding three gems: 
```
gem 'sidekiq'
gem 'redis'
gem 'http'
```
The purpose of this is do have all the webhook events queue and cache in a way for the application to process asynchronously. The http library are meant for us to send webhook event to webhook endpoints.

Next up, we create a directory in "app/workers" for our worker class to live in. This will keep our Sidekiq workers distinct from any ActiveJobs.
```
$ mkdir app/workers
$ touch app/workers/webhook_worker.rb
```
Do remeber to register this path in eager loading.
"config/application.rb"
```
config.eager_load_paths += %W( #{config.root}/workers)
```

Now for the base logic of our webhook worker, it's going to accept a webhook ID as an input parameter, use that to query the endpoint, then post the event payload to the endpoint url. If it fails, it will retry.
```ruby
require 'http.rb'

class WebhookWorker
  include Sidekiq::Worker

  def perform(webhook_event_id)
    webhook_event = WebhookEvent.find_by(id: webhook_event_id)
    return if
      webhook_event.nil?

    webhook_endpoint = webhook_event.webhook_endpoint
    return if
      webhook_endpoint.nil?

    # Send the webhook request with a 30 second timeout.
    response = HTTP.timeout(30)
                   .headers(
                     'User-Agent' => 'rails_webhook_system/1.0',
                     'Content-Type' => 'application/json',
                   )
                   .post(
                     webhook_endpoint.url,
                     body: {
                       event: webhook_event.event,
                       payload: webhook_event.payload,
                     }.to_json
                   )

    # Raise a failed request error and let Sidekiq handle retrying.
    raise FailedRequestError unless
      response.status.success?
  end

  private

  # General failed request error that we're going to use to signal
  # Sidekiq to retry our webhook worker.
  class FailedRequestError < StandardError; end
end
```

The webhook system is actually relatively simple. Since we leaning on Sidekiq to handle queuing, processing and retries, all we need to do is handle the delivery. We attempting the delviery by sending an HTTP POST request to the endpoint's URL with a JSON-encoded payload:
```
{
  "event": "events.test",
  "payload": {
    "test": 1
  }
}
```

### Delivering our first webhook 
Let's try to deliver webhok for the first time 
```
$ rails c
> WebhookWorker.new.perform(WebhookEvent.last.id)
# => Traceback (most recent call last):
#      2: from (irb):1
#      1: from app/workers/webhook_worker.rb:24:in `perform'
#    HTTP::TimeoutError (execution expired)
```
Unless we happen to have a server running at the endpoint that we've entered, we should expecting a timeout after 30 seconds.

#### Handling delivery timeouts 
We'll update the "webhook_worker.rb" file by adding the following lines:
```ruby 
  def perform(webhook_event_id)
    ... 
  rescue HTTP::TimeoutError 

  end
```

We are free to handling the timeour error after the rescue block. However, that is not our focus here, and at the basic level, the error can be logged or stored. For a better result, we should store the whole response which is more informative in any scenario.

Let's go ahead with generating a mgiration.
```
$ rails g migration AddResponseToWebhookEvents
``

```ruby
class AddResponseToWebhookEvents < ActiveRecord::Migration[5.2]
  def change
    add_column :webhook_events, :response, :jsonb, default: {}
  end
end
```

Some further updates on "webhook_worker.rb":
```ruby 
def perform(webhook_event_id)
  webhook_event = WebhookEvent.find_by(id: webhook_event_id)
  return if
    webhook_event.nil?

  webhook_endpoint = webhook_event.webhook_endpoint
  return if
    webhook_endpoint.nil?

  # Send the webhook request with a 30 second timeout.
  response = HTTP.timeout(30)
                 .headers(
                   'User-Agent' => 'rails_webhook_system/1.0',
                   'Content-Type' => 'application/json',
                 )
                 .post(
                   webhook_endpoint.url,
                   body: {
                     event: webhook_event.event,
                     payload: webhook_event.payload,
                   }.to_json
                 )

  # Store the webhook response.
  webhook_event.update(response: {
    headers: response.headers.to_h,
    code: response.code.to_i,
    body: response.body.to_s,
  })

  # Raise a failed request error and let Sidekiq handle retrying.
  raise FailedRequestError unless
    response.status.success?
rescue HTTP::TimeoutError
  # This error means the webhook endpoint timed out. We can either
  # raise a failed request error to trigger a retry, or leave it
  # as-is and consider timeouts terminal. We'll do the latter.
  webhook_event.update(response: { error: 'TIMEOUT_ERROR' })
end
```

Now that we have some handling on the timeours, lets try another delivery:
```
$ rails c
> WebhookWorker.new.perform(WebhookEvent.last.id)
# => true
> WebhookEvent.last.response
# => { "error" => "TIMEOUT_ERROR" }
```

NOTE: IF THE DOMAIN ITSELF IS NOT EXISTED, IT WILL POP ConnectionError and hence timeout error is not registered. As such, the sample code is temporarily using ConnectionError.

Now lets shift our test to localhost:3000.
```
$ rails c
> WebhookEndpoint.last.update!(url: 'http://localhost:3000/webhooks')
# => true

> WebhookWorker.new.perform(WebhookEvent.last.id)
# => Traceback (most recent call last):
#      2: from (irb):17
#      1: from app/workers/webhook_worker.rb:76:in `perform'
#    WebhookWorker::FailedRequestError (WebhookWorker::FailedRequestError)
> WebhookEvent.last.response
# => { "body" => "...", "code" => 404, "headers" => { ... } }
```

As we can see, the worker is correctly raising the failed request error for the 404 response, which will signal Sidekiq to automatically retry the job. And you should also see a line in your server logs indicating 404.
```
ActionController::RoutingError (No route matches [POST] "/webhooks"):
```

Well, of coure all we need to do is define the routes:
```ruby
Rails.application.routes.draw do
  post '/webhooks', to: proc { [204, {}, []] }
end
```
and let's go with another delivery attempt , we should expect a 204 response.
```
$ rails c
> WebhookWorker.new.perform(WebhookEvent.last.id)
# => nil
> WebhookEvent.last.response
# => { "body" => "", "code" => 204, "headers" => { ... } }
```
Additionally, we should also see a server log indicating that the request was sent: 
```
Started POST "/webhooks" for ::1 at 2021-06-15 10:04:34 -0500
```

## Braodcasting our webhook events
Creating webhook events and devlivering from console were mostly for logic testing purposes. In real world, there are cases where multiple events were being sent at the sametme. 

We will create a service object that helps to streamline the process of broadcasting new events to our webhook endpoints.

Let's create a new services directory.
```
$ mkdir app/services
$ touch app/services/broadcast_webhook_service.rb
```