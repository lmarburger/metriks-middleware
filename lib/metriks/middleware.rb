require 'metriks'

module Metriks
  class Middleware
    VERSION = '0.0.1'

    def initialize(app, options = {})
      @app  = app
      @name = options.fetch :name, 'app'
    end

    def call(env)
      time_response(env) do
        record_heroku_queue_status env
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

      Metriks.histogram("#{ @name }.queue.wait") .update(queue_wait.to_i)  if queue_wait
      Metriks.histogram("#{ @name }.queue.depth").update(queue_depth.to_i) if queue_depth
    end

    def call_downstream(env)
      @app.call env
    end

    def response_timer
      Metriks.timer(@name)
    end
  end
end
