require 'sinatra'
require 'sinatra/reloader'
require 'json/ext'
require 'haml'
require 'uri'
require 'prometheus/client'
require 'rufus-scheduler'
require 'logger'
require 'faraday'
require_relative 'helpers'

# Dependent services
POST_SERVICE_HOST ||= ENV['POST_SERVICE_HOST'] || '127.0.0.1'
POST_SERVICE_PORT ||= ENV['POST_SERVICE_PORT'] || '4567'
COMMENT_SERVICE_HOST ||= ENV['COMMENT_SERVICE_HOST'] || '127.0.0.1'
COMMENT_SERVICE_PORT ||= ENV['COMMENT_SERVICE_PORT'] || '4567'
POST_URL ||= "http://#{POST_SERVICE_HOST}:#{POST_SERVICE_PORT}"
COMMENT_URL ||= "http://#{COMMENT_SERVICE_HOST}:#{COMMENT_SERVICE_PORT}"

# App version
VERSION ||= File.read('VERSION').strip
@@version = VERSION

configure do
  http_client = Faraday.new do |faraday|
    faraday.request :url_encoded # form-encode POST params
    faraday.adapter Faraday.default_adapter # make requests with Net::HTTP
  end
  set :http_client, http_client
  set :bind, '0.0.0.0'
  set :server, :puma
  set :logging, false
  set :mylogger, Logger.new(STDOUT)
  enable :sessions
end

# before each request
before do
  session[:flashes] = [] if session[:flashes].class != Array
  env['rack.logger'] = settings.mylogger # set custom logger
end

# after each request
after do
  request_id = env['REQUEST_ID'] || 'null'
  logger.info("service=ui | event=request | path=#{env['REQUEST_PATH']} | " \
              "request_id=#{request_id} | " \
              "remote_addr=#{env['REMOTE_ADDR']} | " \
              "method= #{env['REQUEST_METHOD']} | " \
              "response_status=#{response.status}")
end

# show all posts
get '/' do
  @title = 'All posts'
  begin
    @posts = http_request('get', "#{POST_URL}/posts")
  rescue StandardError => e
    flash_danger('Can\'t show blog posts, some problems with the post ' \
                 'service. <a href="." class="alert-link">Refresh?</a>')
    log_event('error', 'show_all_posts',
              "Failed to read from Post service. Reason: #{e.message}")
  else
    log_event('info', 'show_all_posts',
              'Successfully showed the home page with posts')
  end
  @flashes = session[:flashes]
  session[:flashes] = nil
  haml :index
end

# show a form for creating a new post
get '/new' do
  @title = 'New post'
  @flashes = session[:flashes]
  session[:flashes] = nil
  haml :create
end

# talk to Post service in order to creat a new post
post '/new/?' do
  if params['link'] =~ URI::DEFAULT_PARSER.regexp[:ABS_URI]
    begin
      http_request('post', "#{POST_URL}/add_post", title: params['title'],
                                                   link: params['link'],
                                                   created_at: Time.now.to_i)
    rescue StandardError => e
      flash_danger("Can't save your post, some problems with the post service")
      log_event('error', 'post_create',
                "Failed to create a post. Reason: #{e.message}", params)
    else
      flash_success('Post successuly published')
      log_event('info', 'post_create', 'Successfully created a post', params)
    end
    redirect '/'
  else
    flash_danger('Invalid URL')
    log_event('warning', 'post_create', 'Invalid URL', params)
    redirect back
  end
end

# talk to Post service in order to vote on a post
post '/post/:id/vote/:type' do
  begin
    http_request('post', "#{POST_URL}/vote", id: params[:id],
                                             type: params[:type])
  rescue StandardError => e
    flash_danger('Can\'t vote, some problems with the post service')
    log_event('error', 'vote',
              "Failed to vote. Reason: #{e.message}", params)
  else
    log_event('info', 'vote', 'Successful vote', params)
  end
  redirect back
end

# show a specific post
get '/post/:id' do
  begin
    @post = http_request('get', "#{POST_URL}/post/#{params[:id]}")
  rescue StandardError => e
    log_event('error', 'show_post',
              "Counldn't show the post. Reason: #{e.message}", params)
    halt 404, 'Not found'
  end

  begin
    @comments = http_request('get', "#{COMMENT_URL}/#{params[:id]}/comments")
  rescue StandardError => e
    log_event('error', 'show_post',
              "Counldn't show the comments. Reason: #{e.message}", params)
    # flash_danger("Can't show comments, some problems with the comment service")
  else
    log_event('info', 'show_post',
              'Successfully showed the post', params)
  end
  @flashes = session[:flashes]
  session[:flashes] = nil
  haml :show
end

# talk to Comment service in order to comment on a post
post '/post/:id/comment' do
  begin
    http_request('post', "#{COMMENT_URL}/add_comment",
                 post_id: params[:id],
                 name: params[:name],
                 email: params[:email],
                 created_at: Time.now.to_i,
                 body: params[:body])
  rescue StandardError => e
    log_event('error', 'create_comment',
              "Counldn't create a comment. Reason: #{e.message}", params)
    flash_danger("Can\'t save the comment,
                 some problems with the comment service")
  else
    log_event('info', 'create_comment',
              'Successfully created a new post', params)

    flash_success('Comment successuly published')
  end
  redirect back
end

# health check endpoint
get '/healthcheck' do
  http_healthcheck_handler(POST_URL, COMMENT_URL, VERSION)
end

get '/*' do
  halt 404, 'Page not found'
end
