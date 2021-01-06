# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# We add non-essential gems like debugging tools and CI dependencies
# here. This also allows us to use conditional dependencies that depend on the
# platform

not_jruby = %i[ruby mingw x64_mingw].freeze

gem 'activesupport', '>= 4.2'
gem 'bundler', '>= 1.17', '< 3'
gem 'byebug', platforms: not_jruby
gem 'irb', '~> 1.0'
gem 'redcarpet', '~> 3.5', platforms: not_jruby
gem 'rspec_junit_formatter', '~> 0.4'
gem 'simplecov', '>= 0.17.1'
# 0.8 is incompatible with simplecov < 0.18
# https://github.com/fortissimo1997/simplecov-lcov/pull/25
gem 'simplecov-lcov', '~> 0.7', '< 0.8'
gem 'yard', '~> 0.9.25', platforms: not_jruby

if ENV['REDIS_VERSION']
  gem 'redis', "~> #{ENV['REDIS_VERSION']}"
end
