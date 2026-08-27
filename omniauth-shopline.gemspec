# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "omniauth-shopline/version"

Gem::Specification.new do |spec|
  spec.name          = "omniauth-shopline"
  spec.version       = Omniauth::Shopline::VERSION
  spec.authors       = ["Dropstream"]
  spec.email         = ["karl.falconer@getdropstream.com"]

  spec.summary       = "OmniAuth strategy for SHOPLINE"
  spec.description   = "In this gem you will find an OmniAuth SHOPLINE strategy"
  spec.homepage      = "https://github.com/dropstream/omniauth-shopline"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.2"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"]      = spec.homepage
  spec.metadata["changelog_uri"]     = "#{spec.homepage}/blob/master/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Ship only the library itself; development scaffolding stays out of the gem.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.match(%r{\A(?:spec|bin|pkg|gemfiles|\.github)/}) ||
        f.match(%r{\A(?:\.gitignore|\.rspec|\.ruby-version|\.ruby-gemset|Gemfile|Gemfile\.lock|Rakefile)\z})
    end
  end
  spec.require_paths = ["lib"]

  # Deliberately loose. This is a plugin: a ceiling here becomes a ceiling in every
  # consuming application, so it allows the next major of both gems rather than
  # blocking upgrades on the day one ships. The floors are where OmniAuth 2 support
  # actually begins -- omniauth-oauth2 1.8.0 is its first release to require
  # `omniauth ~> 2.0` -- and CI runs the suite against those floors as well as against
  # the newest resolvable versions.
  spec.add_dependency "omniauth", ">= 2.0", "< 4"
  spec.add_dependency "omniauth-oauth2", ">= 1.8", "< 3"
end
