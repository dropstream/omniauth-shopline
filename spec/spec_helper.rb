require 'bundler/setup'
require 'rspec'
require 'rack/test'
require 'omniauth-shopline'

RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end