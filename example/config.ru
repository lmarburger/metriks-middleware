$: << 'lib'
require 'metriks/middleware'
require 'metriks/reporter/logger'
require 'pp'

$stdout.sync = true
Thread.abort_on_exception = true

Metriks::Reporter::Logger.new(logger: Logger.new($stdout), interval: 5).start
use Metriks::Middleware

run(->(env) do
  case env['PATH_INFO']
  when '/sync'
    [200, {'Content-Type' => 'text/plain'}, ['sync!']]

  when '/sync-error'
    [500, {'Content-Type' => 'text/plain'}, ['sync error!']]

  when '/async'
    Thread.new do
      sleep 1
      env['async.callback'].call([200, {'Content-Type' => 'text/plain'}, ['async!']])
    end
    [-1, {}, []]

  when '/async-error'
    Thread.new do
      sleep 1
      env['async.callback'].call([500, {'Content-Type' => 'text/plain'}, ['async error!']])
    end
    [-1, {}, []]

  else
    world = env.keys.sort.each_with_object({}) {|key, world|
      world[key] = env[key]
    }
    [200, {'Content-Type' => 'text/plain'}, [world.pretty_inspect]]
  end
end)
