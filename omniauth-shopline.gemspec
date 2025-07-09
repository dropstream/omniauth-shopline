# -*- encoding: utf-8 -*-
require File.expand_path('../lib/omniauth-shopline/version', __FILE__)

Gem::Specification.new do |spec|
  spec.name          = "omniauth-shopline"
  spec.authors       = ["Dropstream"]
  spec.email         = [""]
  spec.description   = %q{Omniauth OAuth2 strategy for Shopline}
  spec.summary       = %q{Omniauth OAuth2 strategy for Shopline}
  spec.homepage      = "https://github.com/dropstream/omniauth-shopline"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($\)
  spec.executables   = spec.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  spec.version       = Omniauth::Shopline::VERSION

  spec.add_runtime_dependency 'omniauth-oauth2', '~> 1.6'
  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rack-test"
end