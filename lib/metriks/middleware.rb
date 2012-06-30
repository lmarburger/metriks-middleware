require 'metriks'

module Metriks
  class Middleware
    VERSION = '0.0.1'

    def initialize(app)
      @app = app
    end

    def call(env)
      time_response(env) do
        record_heroku_status env
        call_downstream env
      end
    end

  protected

    def time_response(env, &block)
      if env.has_key? 'async.close'
        context = response_timer.time
        env['async.close'].callback do context.stop end
        block.call
      else
        response_timer.time &block
      end
    end

    def record_heroku_status(env)
      queue_wait   = env['HTTP_X_HEROKU_QUEUE_WAIT_TIME']
      queue_depth  = env['HTTP_X_HEROKU_QUEUE_DEPTH']
      dynos_in_use = env['HTTP_X_HEROKU_DYNOS_IN_USE']

      Metriks.histogram('app.queue.wait') .update(queue_wait.to_i)   if queue_wait
      Metriks.histogram('app.queue.depth').update(queue_depth.to_i)  if queue_depth
      Metriks.histogram('app.dynos')      .update(dynos_in_use.to_i) if dynos_in_use
    end

    def call_downstream(env)
      @app.call env
    end

    def response_timer
      Metriks.timer 'app'
    end
  end
end
