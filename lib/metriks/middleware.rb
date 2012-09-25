require 'metriks'

module Metriks
  class Middleware
    VERSION = '1.2.0'

    def initialize(app)
      @app = app
    end

    def call(env)
      time_response(env) do
        record_heroku_queue_status env
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

    def record_heroku_queue_status(env)
      queue_wait   = env['HTTP_X_HEROKU_QUEUE_WAIT_TIME']
      queue_depth  = env['HTTP_X_HEROKU_QUEUE_DEPTH']

      Metriks.histogram("queue.wait") .update(queue_wait.to_i)  if queue_wait
      Metriks.histogram("queue.depth").update(queue_depth.to_i) if queue_depth
    end

    def record_error_rate(env)
      original_callback = env['async.callback']
      env['async.callback'] = lambda do |env|
        record_error env.first
        original_callback.call env
      end
    end

    def call_downstream(env)
      response = @app.call env
      record_error response.first
      response
    end

    def record_error(status)
      if status >= 500
        Metriks.meter("responses.error").mark
      elsif status == 404
        Metriks.meter("responses.not_found").mark
      end
    end

    def response_timer
      Metriks.timer('app')
    end
  end
end
