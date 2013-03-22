require 'metriks'

module Metriks
  class Middleware
    VERSION = '2.1.0'

    REQUEST_DELAY              = 'request_delay'
    ERROR_RESPONSE             = 'responses.error'
    NOT_FOUND_RESPONSE         = 'responses.not_found'
    NOT_MODIFIED_RESPONSE      = 'responses.not_modified'
    CONTENT_LENGTH             = 'responses.content_length'
    REQUEST_START_HEADER       = 'HTTP_X_REQUEST_START'

    def initialize(app)
      @app = app
    end

    def call(env)
      time_response(env) do
        record_request_delay env
        record_response env
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

    def record_request_delay(env)
      delay = duration_since_request_start(env)
      Metriks.histogram(REQUEST_DELAY).update(delay)
    end

    def record_response(env)
      original_callback = env['async.callback']
      env['async.callback'] = lambda do |(status, headers, body)|
        record_staus_code status
        record_content_length headers
        original_callback.call [status, headers, body]
      end
    end

    def call_downstream(env)
      status, headers, body = @app.call env
      record_staus_code status
      record_content_length headers

      [status, headers, body]
    end

    def record_staus_code(status)
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
