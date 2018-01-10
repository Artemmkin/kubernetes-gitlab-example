def flash_danger(message)
  session[:flashes] << { type: 'alert-danger', message: message }
end

def flash_success(message)
  session[:flashes] << { type: 'alert-success', message: message }
end

def log_event(type, name, message, params = '{}')
  case type
  when 'error'
    logger.error('service=ui | ' \
                 "event=#{name} | " \
                 "request_id=#{request.env['REQUEST_ID']} | " \
                 "message=\'#{message}\' | " \
                 "params: #{params.to_json}")
  when 'info'
    logger.info('service=ui | ' \
                "event=#{name} | " \
                "request_id=#{request.env['REQUEST_ID']} | " \
                "message=\'#{message}\' | " \
                "params: #{params.to_json}")
  when 'warning'
    logger.warn('service=ui | ' \
                "event=#{name} | " \
                "request_id=#{request.env['REQUEST_ID']} | " \
                "message=\'#{message}\' |  " \
                "params: #{params.to_json}")
  end
end

def http_request(method, url, params = {})
  unless defined?(request).nil?
    settings.http_client.headers[:request_id] = request.env['REQUEST_ID'].to_s
  end

  case method
  when 'get'
    response = settings.http_client.get url
    JSON.parse(response.body)
  when 'post'
    settings.http_client.post url, params
  end
end

def http_healthcheck_handler(post_url, comment_url, version)
  post_status = check_service_health(post_url)
  comment_status = check_service_health(comment_url)

  status = if comment_status == 1 && post_status == 1
             1
           else
             0
           end

  healthcheck = { status: status,
                  dependent_services: {
                    comment: comment_status,
                    post:    post_status
                  },
                  version: version }
  healthcheck.to_json
end

def check_service_health(url)
  name = http_request('get', "#{url}/healthcheck")
rescue StandardError
  0
else
  name['status']
end

def set_health_gauge(metric, value)
  metric.set(
    {
      version: VERSION
    },
    value
  )
end
