# frozen_string_literal: true

module Faulty
  module Events
    # All possible events that can be raised by Faulty
    EVENTS = %i[
      circuit_success
      circuit_failure
      circuit_skipped
      circuit_opened
      circuit_closed
      cache_failure
      storage_failure
    ].freeze
  end
end
