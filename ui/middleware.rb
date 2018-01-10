require 'prometheus/client'

class Metrics
  def initialize(app)
    @app = app
    prometheus = Prometheus::Client.registry
    @request_count = Prometheus::Client::Counter.new(
      :ui_request_count,
      'App request rount'
    )
    @request_response_time = Prometheus::Client::Histogram.new(
      :ui_request_response_time,
      'Request response time'
    )
    prometheus.register(@request_response_time)
    prometheus.register(@request_count)
  end

  def call(env)
    request_started_on = Time.now
    env['REQUEST_ID'] = SecureRandom.uuid # add unique ID to each request
    @status, @headers, @response = @app.call(env)
    request_ended_on = Time.now
    # prometheus metrics
    @request_response_time.observe({ path: env['REQUEST_PATH'] },
                             request_ended_on - request_started_on)
    @request_count.increment(method: env['REQUEST_METHOD'],
                             path: env['REQUEST_PATH'],
                             http_status: @status)
    [@status, @headers, @response]
  end
end
