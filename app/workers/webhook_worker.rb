require 'http'

class WebhookWorker 
  include Sidekiq::Worker 

  def perform(webhook_event_id)
    webhook_event = WebhookEvent.find_by(id: webhook_event_id)
    return if
      webhook_event.nil?

    webhook_endpoint = webhook_event.webhook_endpoint 
    return if 
      webhook_endpoint.nil? 

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

    # Raise a failed request error and let Sidekiq handle retrying 
    raise FailedRequestError unless 
      response.status.success?
  end

  private 

  class FailedRequestError < StandardError; end
end