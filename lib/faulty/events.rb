# frozen_string_literal: true

class Faulty
  # The namespace for Faulty events and event listeners
  module Events
    # All possible events that can be raised by Faulty
    EVENTS = %i[
      cache_failure
      circuit_cache_hit
      circuit_cache_miss
      circuit_cache_write
      circuit_closed
      circuit_failure
      circuit_opened
      circuit_reopened
      circuit_skipped
      circuit_success
      storage_failure
    ].freeze

    EVENT_SET = Set.new(EVENTS)
  end
end

require 'faulty/events/callback_listener'
require 'faulty/events/honeybadger_listener'
require 'faulty/events/log_listener'
require 'faulty/events/notifier'
