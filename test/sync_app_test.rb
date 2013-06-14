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
    response   = [200, {}, ['']]
    downstream = mock
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

  def test_records_content_length
    length_app = lambda do |env| [200, { 'Content-Length' => 42 }, ['']] end
    Metriks::Middleware.new(length_app).call(@env)

    count = Metriks.histogram('responses.content_length').count
    size  = Metriks.histogram('responses.content_length').mean

    assert_equal 1,  count
    assert_equal 42, size
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

  def test_records_not_modified_responses
    not_modified_app = lambda do |env| [304, {}, ['']] end
    2.times { Metriks::Middleware.new(not_modified_app).call(@env) }
    Metriks::Middleware.new(@downstream).call(@env)

    not_modifieds = Metriks.meter('responses.not_modified').count
    assert_equal 2, not_modifieds
  end

  def test_omits_request_delay
    Metriks::Middleware.new(@downstream).call(@env)

    used = Metriks.histogram('request_delay').mean
    assert_equal 0, used
  end

  def test_records_request_delay
    now   = Time.now.to_f * 1000
    start = now - 42
    @env.merge! 'HTTP_X_REQUEST_START' => start.to_s
    Metriks::Middleware.new(@downstream).call(@env)

    delay = Metriks.histogram('request_delay').mean
    assert_in_delta 42, delay, 1
  end

  def test_ignores_future_request_start_time
    now   = Time.now.to_f * 1000
    start = now + 42
    @env.merge! 'HTTP_X_REQUEST_START' => start.to_s
    Metriks::Middleware.new(@downstream).call(@env)

    delay = Metriks.histogram('request_delay').mean
    assert_equal 0, delay
  end

  def test_records_string_statuses
    error_app = lambda do |env| ['500', {}, ['']] end
    2.times { Metriks::Middleware.new(error_app).call(@env) }
    Metriks::Middleware.new(@downstream).call(@env)

    errors = Metriks.meter('responses.error').count
    assert_equal 2, errors
  end

  def test_ignores_non_integer_statuses
    error_app = lambda do |env| ['fail', {}, ['']] end
    2.times { Metriks::Middleware.new(error_app).call(@env) }
    Metriks::Middleware.new(@downstream).call(@env)

    errors        = Metriks.meter('responses.error').count
    not_founds    = Metriks.meter('responses.not_found').count
    not_modifieds = Metriks.meter('responses.not_modified').count
    assert_equal 0, errors
    assert_equal 0, not_founds
    assert_equal 0, not_modifieds
  end
end
