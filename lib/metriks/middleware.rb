require 'metriks'

module Metriks
  class Middleware
    VERSION = '1.3.0'

    def initialize(app)
      @app = app
    end

    def call(env)
      time_response(env) do
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

    def record_heroku_status(env)
      queue_wait   = duration_since_request_start(env)
      queue_depth  = env['HTTP_X_HEROKU_QUEUE_DEPTH']
      dynos_in_use = env['HTTP_X_HEROKU_DYNOS_IN_USE']

      Metriks.histogram("queue.wait")  .update(queue_wait)        if queue_wait
      Metriks.histogram("queue.depth") .update(queue_depth.to_i)  if queue_depth
      Metriks.histogram("dynos.in_use").update(dynos_in_use.to_i) if dynos_in_use
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
        Metriks.meter("responses.error").mark
      elsif status == 404
        Metriks.meter("responses.not_found").mark
      elsif status == 304
        Metriks.meter("responses.not_modified").mark
      end
    end

    def record_content_length(headers)
      content_length = headers.fetch('Content-Length', 0).to_i
      return unless content_length > 0
      Metriks.histogram('responses.content_length').update(content_length)
    end

    def response_timer
      Metriks.timer('app')
    end

    def duration_since_request_start(env)
      request_start = env['HTTP_X_REQUEST_START']
      return unless request_start
      duration   = ((Time.now.to_f * 1_000) - request_start.to_f).round
      [ duration, 0 ].max
    end
  end
end
