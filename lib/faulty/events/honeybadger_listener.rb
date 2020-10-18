# frozen_string_literal: true

class Faulty
  module Events
    # Reports circuit errors to Honeybadger
    #
    # https://www.honeybadger.io/
    #
    # The honeybadger gem must be available.
    class HoneybadgerListener
      # (see ListenerInterface#handle)
      def handle(event, payload)
        return unless EVENTS.include?(event)

        send(event, payload) if respond_to?(event, true)
      end

      private

      def circuit_failure(payload)
        _circuit_error(payload)
      end

      def circuit_opened(payload)
        _circuit_error(payload)
      end

      def circuit_reopened(payload)
        _circuit_error(payload)
      end

      def cache_failure(payload)
        Honeybadger.notify(payload[:error], context: {
          action: payload[:action],
          key: payload[:key]
        })
      end

      def storage_failure(payload)
        Honeybadger.notify(payload[:error], context: {
          action: payload[:action],
          circuit: payload[:circuit]&.name
        })
      end

      def _circuit_error(payload)
        Honeybadger.notify(payload[:error], context: {
          circuit: payload[:circuit].name
        })
      end
    end
  end
end
