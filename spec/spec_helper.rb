# frozen_string_literal: true

require 'byebug' if Gem.loaded_specs['byebug']

if ENV['COVERAGE'] || ENV['CI']
  require 'simplecov'
  if ENV['CI']
    require 'simplecov-lcov'
    SimpleCov::Formatter::LcovFormatter.config.report_with_single_file = true
    SimpleCov.formatter = SimpleCov::Formatter::LcovFormatter
  end

  SimpleCov.start do
    if Gem::Version.new(SimpleCov::VERSION) >= Gem::Version.new('0.18.0')
      enable_coverage :branch
    end
    add_filter '/spec/'
    add_filter '/vendor/'
  end
end

require 'faulty'
require 'faulty/patch/redis'
require 'faulty/patch/elasticsearch'
require 'timecop'
require 'redis'
require 'json'
require 'connection_pool'

begin
  # We don't test Mysql2 on Ruby 2.3 since that would require
  # installing an old EOL version of OpenSSL
  require 'faulty/patch/mysql2' if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.4')
rescue LoadError
  # Ok if mysql2 isn't available
end

require_relative 'support/concurrency'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.disable_monkey_patching!
  config.warnings = false

  config.before do
    allow(Faulty).to receive(:current_time) do
      Time.now.to_f
    end
  end

  config.after do
    Timecop.return
    Faulty.enable!
  end

  config.include Faulty::Specs::Concurrency
end
