# frozen_string_literal: true

module Faulty
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
  end
end
