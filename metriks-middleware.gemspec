lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'metriks/middleware/version'

Gem::Specification.new do |spec|
  spec.name        = 'metriks-middleware'
  spec.version     = Metriks::Middleware::VERSION
  spec.summary     = "Rack middleware for metriks"
  spec.description = "Rack middleware to track throughput and response time with metriks."
  spec.authors     = ["Larry Marburger"]
  spec.email       = 'larry@marburger.cc'
  spec.homepage    = 'https://github.com/lmarburger/metriks-middleware'
  spec.licenses    = ['MIT']

  spec.add_dependency 'metriks', '~> 0.9.9'
  spec.add_development_dependency 'mocha', '~> 0.11.4'
  spec.add_development_dependency 'rake', '>= 0.9'

  spec.files = %w(Gemfile LICENSE README.md Rakefile)
  spec.files << "metriks-middleware.gemspec"
  spec.files += Dir.glob("lib/**/*.rb")
  spec.files += Dir.glob("test/**/*.rb")
  spec.files += Dir.glob("script/*")
  spec.test_files = Dir.glob("test/**/*.rb")

  spec.required_rubygems_version = '>= 1.3.6'
end
