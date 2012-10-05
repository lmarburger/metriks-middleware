require 'test_helper'

require 'metriks/middleware'

class AsyncAppTest < Test::Unit::TestCase
  class AsyncClose
    def callback(&block) @callback = block     end
    def call(*args)      @callback.call(*args) end
  end

  def setup
    @async_close    = AsyncClose.new
    @async_callback = ->(env) do @response = env end
    @env = { 'async.close' => @async_close, 'async.callback' => @async_callback }
    @downstream = lambda do |env|
      env['async.callback'].call [200, {}, ['']]
      [-1, {}, ['']]
    end
  end

  def teardown
    Metriks::Registry.default.each do |_, metric| metric.clear end
  end

  def test_calls_downstream
    downstream = mock
    response   = stub first: 42
    downstream.expects(:call).with(@env).returns(response)

    actual_response = Metriks::Middleware.new(downstream).call(@env)

    assert_equal response, actual_response
  end

  def test_calls_original_callback
    Metriks::Middleware.new(@downstream).call(@env)

    assert_equal [200, {}, ['']], @response
  end

  def test_counts_throughput
    Metriks::Middleware.new(@downstream).call(@env)
    @async_close.call

    count = Metriks.timer('app').count

    assert_equal 1, count
  end

  def test_times_downstream_response
    sleepy_app = ->(env) do
      sleep 0.1
      @downstream.call env
    end

    Metriks::Middleware.new(sleepy_app).call(@env)
    @async_close.call

    time  = Metriks.timer('app').mean

    assert_in_delta 0.1, time, 0.01
  end

  def test_records_error_responses
    error_sync_app  = lambda do |env| [500, {}, ['']] end
    error_async_app = lambda do |env|
      env['async.callback'].call [500, {}, ['']]
      [-1, {}, ['']]
    end

    success_sync_app  = lambda do |env| [200, {}, ['']] end
    success_async_app = lambda do |env|
      env['async.callback'].call [200, {}, ['']]
      [-1, {}, ['']]
    end

    Metriks::Middleware.new(error_sync_app).call(@env.dup)
    Metriks::Middleware.new(error_async_app).call(@env.dup)
    Metriks::Middleware.new(success_sync_app).call(@env.dup)
    Metriks::Middleware.new(success_async_app).call(@env.dup)

    errors = Metriks.meter('responses.error').count

    assert_equal 2, errors
  end

  def test_records_not_found_responses
    not_found_sync_app  = lambda do |env| [404, {}, ['']] end
    not_found_async_app = lambda do |env|
      env['async.callback'].call [404, {}, ['']]
      [-1, {}, ['']]
    end

    success_sync_app  = lambda do |env| [200, {}, ['']] end
    success_async_app = lambda do |env|
      env['async.callback'].call [200, {}, ['']]
      [-1, {}, ['']]
    end

    Metriks::Middleware.new(not_found_sync_app).call(@env.dup)
    Metriks::Middleware.new(not_found_async_app).call(@env.dup)
    Metriks::Middleware.new(success_sync_app).call(@env.dup)
    Metriks::Middleware.new(success_async_app).call(@env.dup)

    not_founds = Metriks.meter('responses.not_found').count

    assert_equal 2, not_founds
  end

  def test_records_not_modified_responses
    not_modified_sync_app  = lambda do |env| [304, {}, ['']] end
    not_modified_async_app = lambda do |env|
      env['async.callback'].call [304, {}, ['']]
      [-1, {}, ['']]
    end

    success_sync_app  = lambda do |env| [200, {}, ['']] end
    success_async_app = lambda do |env|
      env['async.callback'].call [200, {}, ['']]
      [-1, {}, ['']]
    end

    Metriks::Middleware.new(not_modified_sync_app).call(@env.dup)
    Metriks::Middleware.new(not_modified_async_app).call(@env.dup)
    Metriks::Middleware.new(success_sync_app).call(@env.dup)
    Metriks::Middleware.new(success_async_app).call(@env.dup)

    not_modifieds = Metriks.meter('responses.not_modified').count

    assert_equal 2, not_modifieds
  end

  def test_omits_queue_metrics
    Metriks::Middleware.new(@downstream).call(@env)
    @async_close.call

    wait  = Metriks.histogram('queue.wait').mean
    depth = Metriks.histogram('queue.depth').mean

    assert_equal 0, wait
    assert_equal 0, depth
  end

  def test_records_heroku_queue_metrics
    @env.merge! 'HTTP_X_HEROKU_QUEUE_WAIT_TIME' => '42',
                'HTTP_X_HEROKU_QUEUE_DEPTH'     => '24'
    Metriks::Middleware.new(@downstream).call(@env)
    @async_close.call

    wait  = Metriks.histogram('queue.wait').mean
    depth = Metriks.histogram('queue.depth').mean

    assert_equal 42, wait
    assert_equal 24, depth
  end
end
