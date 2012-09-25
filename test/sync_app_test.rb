require 'test_helper'

require 'metriks/middleware'

class SyncAppTest < Test::Unit::TestCase
  def setup
    @env = {}
    @downstream = lambda do |env| [200, {}, ['']] end
  end

  def teardown
    Metriks::Registry.default.each do |_, metric| metric.clear end
  end

  def sleepy_app
    lambda do |env|
      sleep 0.1
      @downstream.call env
    end
  end

  def test_calls_downstream
    downstream = mock
    response   = stub first: 200
    downstream.expects(:call).with(@env).returns(response)

    actual_response = Metriks::Middleware.new(downstream).call(@env)

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

  def test_records_error_responses
    error_app = lambda do |env| [500, {}, ['']] end
    2.times { Metriks::Middleware.new(error_app).call(@env) }
    Metriks::Middleware.new(@downstream).call(@env)

    errors = Metriks.meter('responses.error').count

    assert_equal 2, errors
  end

  def test_records_not_found_responses
    not_found_app = lambda do |env| [404, {}, ['']] end
    2.times { Metriks::Middleware.new(not_found_app).call(@env) }
    Metriks::Middleware.new(@downstream).call(@env)

    not_founds = Metriks.meter('responses.not_found').count

    assert_equal 2, not_founds
  end

  def test_omits_queue_metrics
    Metriks::Middleware.new(@downstream).call(@env)

    wait  = Metriks.histogram('queue.wait').mean
    depth = Metriks.histogram('queue.depth').mean

    assert_equal 0, wait
    assert_equal 0, depth
  end

  def test_records_heroku_queue_metrics
    @env.merge! 'HTTP_X_HEROKU_QUEUE_WAIT_TIME' => '42',
                'HTTP_X_HEROKU_QUEUE_DEPTH'     => '24'
    Metriks::Middleware.new(@downstream).call(@env)

    wait  = Metriks.histogram('queue.wait').mean
    depth = Metriks.histogram('queue.depth').mean

    assert_equal 42, wait
    assert_equal 24, depth
  end
end
