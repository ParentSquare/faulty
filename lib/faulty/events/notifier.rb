# frozen_string_literal: true

module Faulty
  module Events
    # The default event dispatcher for Faulty
    class Notifier
      # @param listeners [Array<ListenerInterface>] An array of event listeners
      def initialize(listeners = [])
        @listeners = listeners.freeze
      end

      # Notify all listeners of an event
      #
      # @param event [Symbol] The event name
      # @param payload [Hash] A hash of event payload data. The payload keys
      #   differ between events, but should be consistent across calls for a
      #   single event
      def notify(event, payload)
        raise ArgumentError, "Unknown event #{event}" unless EVENTS.include?(event)

        @listeners.each { |l| l.handle(event, payload) }
      end
    end
  end
end
