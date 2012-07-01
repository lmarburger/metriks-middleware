require 'test_helper'

require 'metriks/middleware'

class MeterTest < Test::Unit::TestCase
  def setup
    @downstream = lambda do |env| end
    @env = {}
  end

  def teardown
    Metriks::Registry.default.each do |_, metric| metric.clear end
  end

  def sleepy_app
    lambda do |env| sleep(0.1) end
  end

  def async_env(deferrable)
    { 'async.close' => deferrable }
  end

  def test_calls_downstream
    downstream = mock
    response   = stub
    downstream.expects(:call).with(@env).returns(response)
    actual_response = Metriks::Middleware.new(downstream).call(@env)

    assert_equal response, actual_response
  end

  def test_async_app_calls_downstream
    downstream = mock
    response   = stub

    deferrable = Object.new
    def deferrable.callback() yield end
    env = { 'async.close' => deferrable }

    downstream.expects(:call).with(env).returns(response)
    actual_response = Metriks::Middleware.new(downstream).call(env)

    assert_equal response, actual_response
  end

  def test_counts_throughput
    Metriks::Middleware.new(@downstream).call(@env)
    count = Metriks.timer('app').count

    assert_equal 1, count
  end

  def test_times_downstream_response
    Metriks::Middleware.new(sleepy_app).call(@env)
    time = Metriks.timer('app').mean

    assert_in_delta 0.1, time, 0.01
  end

  def test_async_app_stops_timer_on_close
    deferrable = Object.new
    def deferrable.callback(&block) @callback = block end
    def deferrable.call_callback()  @callback.call    end
    env = { 'async.close' => deferrable }

    Metriks::Middleware.new(sleepy_app).call(env)
    deferrable.call_callback
    count = Metriks.timer('app').count
    time  = Metriks.timer('app').mean

    assert_equal 1, count
    assert_in_delta 0.1, time, 0.01
  end

  def test_omits_queue_metrics
    Metriks::Middleware.new(@downstream).call(@env)
    wait  = Metriks.histogram('app.queue.wait').mean
    depth = Metriks.histogram('app.queue.depth').mean

    assert_equal 0, wait
    assert_equal 0, depth
  end

  def test_records_heroku_queue
    env = { 'HTTP_X_HEROKU_QUEUE_WAIT_TIME' => '42',
            'HTTP_X_HEROKU_QUEUE_DEPTH'     => '24' }

    Metriks::Middleware.new(@downstream).call(env)
    wait  = Metriks.histogram('app.queue.wait').mean
    depth = Metriks.histogram('app.queue.depth').mean

    assert_equal 42, wait
    assert_equal 24, depth
  end

  def test_async_records_heroku_queue
    deferrable = Object.new
    def deferrable.callback() yield end
    env = { 'async.close' => deferrable,
            'HTTP_X_HEROKU_QUEUE_WAIT_TIME' => '42',
            'HTTP_X_HEROKU_QUEUE_DEPTH'     => '24' }

    Metriks::Middleware.new(@downstream).call(env)
    wait  = Metriks.histogram('app.queue.wait').mean
    depth = Metriks.histogram('app.queue.depth').mean

    assert_equal 42, wait
    assert_equal 24, depth
  end

  def test_name_merics
    env = { 'HTTP_X_HEROKU_QUEUE_WAIT_TIME' => '42',
            'HTTP_X_HEROKU_QUEUE_DEPTH'     => '24' }
    Metriks::Middleware.new(@downstream, name: 'metric-name').call(env)
    count = Metriks.timer('metric-name').count
    wait  = Metriks.histogram('metric-name.queue.wait').mean
    depth = Metriks.histogram('metric-name.queue.depth').mean

    assert_not_nil count
    assert_not_nil wait
    assert_not_nil depth
  end
end
