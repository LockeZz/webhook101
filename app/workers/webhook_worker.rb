require 'http'

class WebhookWorker 
  include Sidekiq::Worker 

  sidekiq_options retry: 10, dead: false

  sidekiq_retry_in do |retry_count|
    # Exponential backoff, with a random 30-sec to 10-minutes 'jitter'
    # added in to help spread ot any webhook "bursts"
    jtter = rand(30.seconds..10.minutes).to_i

    (retry_count ** 5) + jitter
  end

  def perform(webhook_event_id)
    webhook_event = WebhookEvent.find_by(id: webhook_event_id)
    return if
      webhook_event.nil?

    webhook_endpoint = webhook_event.webhook_endpoint 
    return if 
      webhook_endpoint.nil? 

    return unless 
      webhook_endpoint.subscribed?(webhook_event.event)

    # Send the webhook request with a 30 second timeout 
    response = HTTP.timeout(30).headers(
      'User-Agent' => 'rails_webhook_system/1.0',
      'Content-Type' => 'application/json',
    ).post(
      webhook_endpoint.url,
      body: {
        event: webhook_event.event, 
        payload: webhook_event.payload,
      }.to_json
    )

    # Store the webhook response
    webhook_event.update(response: {
      headers: response.headers.to_h,
      code: response.code.to_i,
      body: response.body.to_s
    })

    # Raise a failed request error and let Sidekiq handle retrying 
    raise FailedRequestError unless 
      response.status.success?
  rescue HTTP::ConnectionError 
    # This error means the webhook endpoint timed out
    # We can raised a failed request error to trigger a retry or leave it
    webhook_event.update(response: {error: 'TIMEOUT_ERROR'})
  end

  private 

  class FailedRequestError < StandardError; end
end