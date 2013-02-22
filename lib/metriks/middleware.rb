require 'metriks'

module Metriks
  class Middleware
    VERSION = '1.3.0'

    REQUEST_WAIT          = 'request.wait'
    HEROKU_QUEUE_WAIT     = 'heroku.queue.wait'
    HEROKU_QUEUE_DEPTH    = 'heroku.queue.depth'
    HEROKU_DYNOS_IN_USE   = 'heroku.dynos.in_use'
    ERROR_RESPONSE        = 'responses.error'
    NOT_FOUND_RESPONSE    = 'responses.not_found'
    NOT_MODIFIED_RESPONSE = 'responses.not_modified'
    CONTENT_LENGTH        = 'responses.content_length'

    QUEUE_WAIT_HEADER     = 'HTTP_X_HEROKU_QUEUE_WAIT_TIME'
    QUEUE_DEPTH_HEADER    = 'HTTP_X_HEROKU_QUEUE_DEPTH'
    DYNOS_IN_USE_HEADER   = 'HTTP_X_HEROKU_DYNOS_IN_USE'
    REQUEST_START_HEADER  = 'HTTP_X_REQUEST_START'

    def initialize(app)
      @app = app
    end

    def call(env)
      time_response(env) do
        record_request_wait env
        record_heroku_status env
        record_error_rate env
        call_downstream env
      end
    end

  protected

    def time_response(env, &handle_request)
      if env.has_key? 'async.close'
        context = response_timer.time
        env['async.close'].callback do context.stop end
        handle_request.call
      else
        response_timer.time &handle_request
      end
    end

    def record_request_wait(env)
      wait = duration_since_request_start(env)
      Metriks.histogram(REQUEST_WAIT).update(wait)
    end

    def record_heroku_status(env)
      queue_wait   = env[QUEUE_WAIT_HEADER]
      queue_depth  = env[QUEUE_DEPTH_HEADER]
      dynos_in_use = env[DYNOS_IN_USE_HEADER]

      if queue_wait
        Metriks.histogram(HEROKU_QUEUE_WAIT).
          update(queue_wait.to_i)
      end

      if queue_depth
        Metriks.histogram(HEROKU_QUEUE_DEPTH).
          update(queue_depth.to_i)
      end

      if dynos_in_use
        Metriks.histogram(HEROKU_DYNOS_IN_USE).
          update(dynos_in_use.to_i)
      end
    end

    def record_error_rate(env)
      original_callback = env['async.callback']
      env['async.callback'] = lambda do |(status, headers, body)|
        record_error status
        record_content_length headers
        original_callback.call [status, headers, body]
      end
    end

    def call_downstream(env)
      status, headers, body = @app.call env
      record_error status
      record_content_length headers

      [status, headers, body]
    end

    def record_error(status)
      if status >= 500
        Metriks.meter(ERROR_RESPONSE).mark
      elsif status == 404
        Metriks.meter(NOT_FOUND_RESPONSE).mark
      elsif status == 304
        Metriks.meter(NOT_MODIFIED_RESPONSE).mark
      end
    end

    def record_content_length(headers)
      content_length = headers.fetch('Content-Length', 0).to_i
      return unless content_length > 0
      Metriks.histogram(CONTENT_LENGTH).update(content_length)
    end

    def response_timer
      Metriks.timer('app')
    end

    def duration_since_request_start(env)
      request_start = env[REQUEST_START_HEADER]
      return 0 unless request_start
      duration = ((Time.now.to_f * 1_000) - request_start.to_f).round
      duration > 0 ? duration : 0
    end
  end
end
