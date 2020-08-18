# frozen_string_literal: true

module Faulty
  module Events
    # The interface required to implement a event listener
    #
    # This is for documentation only and is not loaded
    class ListenerInterface
      # Handle an event raised by Faulty
      #
      # @param event [Symbol] The event name
      # @param payload [Hash] A hash with keys based on the event type
      # @return [void]
      def handle(event, payload)
      end
    end
  end
end
