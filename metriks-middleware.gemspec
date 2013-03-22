lib = "metriks-middleware"
lib_file = File.expand_path("../lib/metriks/middleware.rb", __FILE__)
File.read(lib_file) =~ /\bVERSION\s*=\s*["'](.+?)["']/
version = $1

Gem::Specification.new do |spec|
  spec.specification_version = 2 if spec.respond_to? :specification_version=
  spec.required_rubygems_version = '>= 1.3.6'

  spec.name    = lib
  spec.version = version

  spec.summary     = "Rack middleware for metriks"
  spec.description = "Rack middleware to track throughput and response time with metriks."

  spec.authors  = ["Larry Marburger"]
  spec.email    = 'larry@marburger.cc'
  spec.homepage = 'https://github.com/lmarburger/metriks-middleware'
  spec.licenses = ['MIT']

  spec.add_dependency 'metriks', '~> 0.9.9'
  spec.add_development_dependency 'mocha', '~> 0.11.4'
  spec.add_development_dependency 'rake', '>= 0.9'

  spec.files = %w(Gemfile LICENSE README.md Rakefile)
  spec.files << "#{lib}.gemspec"
  spec.files += Dir.glob("lib/**/*.rb")
  spec.files += Dir.glob("test/**/*.rb")
  spec.files += Dir.glob("script/*")
  spec.test_files = Dir.glob("test/**/*.rb")
end
