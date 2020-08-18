# frozen_string_literal: true

module Faulty
  module Events
    # A simple listener implementation that uses callback blocks as handlers
    class CallbackListener
      def initialize
        @handlers = {}
        yield self if block_given?
      end

      def handle(event, payload)
        return unless EVENTS.include?(event)
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
