# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# We add non-essential gems like debugging tools and CI dependencies
# here. This also allows us to use conditional dependencies that depend on the
# platform

not_jruby = %i[ruby mingw x64_mingw].freeze

gem 'activesupport', '>= 4.2'
gem 'byebug', platforms: not_jruby
# Open source licensed elasticsearch
gem 'honeybadger', '>= 2.0'
gem 'irb', '~> 1.0'
# Minimum of 0.5.0 for specific error classes
gem 'mysql2', '>= 0.5.0', platforms: not_jruby
gem 'redcarpet', '~> 3.5', platforms: not_jruby
gem 'rspec_junit_formatter', '~> 0.4'
gem 'yard', '~> 0.9.25', platforms: not_jruby

if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.6')
  gem 'rubocop', '~> 1.32.0'
  gem 'rubocop-rspec', '~> 2.12'
  gem 'simplecov', '>= 0.17.1'
  gem 'simplecov-cobertura', '~> 2.1'
end

if ENV['REDIS_VERSION']
  gem 'redis', "~> #{ENV['REDIS_VERSION']}"
end

if ENV['SEARCH_GEM']
  name, version = ENV['SEARCH_GEM'].split(':')
  name = 'opensearch-ruby' if name == 'opensearch'
  gem name, "~> #{version}"
else
  gem 'opensearch-ruby', '~> 2.1'
end
