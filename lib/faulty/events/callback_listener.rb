# frozen_string_literal: true

class Faulty
  module Events
    # A simple listener implementation that uses callback blocks as handlers
    #
    # Each event in {EVENTS} has a method on this class that can be used
    # to register a callback for that event.
    #
    # @example
    #   listener = CallbackListener.new
    #   listener.circuit_opened do |payload|
    #     logger.error(
    #       "Circuit #{payload[:circuit].name} opened: #{payload[:error].message}"
    #     )
    #   end
    class CallbackListener
      def initialize
        @handlers = {}
        yield self if block_given?
      end

      # @param (see ListenerInterface#handle)
      # @return [void]
      def handle(event, payload)
        return unless EVENT_SET.include?(event)
        return unless @handlers.key?(event)

        @handlers[event].each do |handler|
          handler.call(payload)
        end
      end

      EVENTS.each do |event|
        define_method(event) do |&block|
          @handlers[event] ||= []
          @handlers[event] << block
        end
      end
    end
  end
end
