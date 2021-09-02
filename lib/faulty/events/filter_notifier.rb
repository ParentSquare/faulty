# frozen_string_literal: true

class Faulty
  module Events
    # Wraps a Notifier and filters events by name
    class FilterNotifier
      # @param notifier [Notifier] The internal notifier to filter events for
      # @param events [Array, nil] An array of events to allow. If nil, all
      #   {EVENTS} will be used
      # @param exclude [Array, nil] An array of events to disallow. If nil,
      #   no events will be disallowed. Takes priority over `events`.
      def initialize(notifier, events: nil, exclude: nil)
        @notifier = notifier
        @events = Set.new(events || EVENTS)
        exclude&.each { |e| @events.delete(e) }
      end

      # Notify all listeners of an event
      #
      # If a listener raises an error while handling an event, that error will
      # be captured and written to STDERR.
      #
      # @param (see Notifier)
      def notify(event, payload)
        return unless @events.include?(event)

        @notifier.notify(event, payload)
      end
    end
  end
end
