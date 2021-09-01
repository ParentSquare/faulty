# frozen_string_literal: true

class Faulty
  module Events
    # Reports circuit errors to Honeybadger
    #
    # https://www.honeybadger.io/
    #
    # The honeybadger gem must be available.
    class HoneybadgerListener
      HONEYBADGER_EVENTS = Set[
        :circuit_failure,
        :circuit_opened,
        :circuit_reopened,
        :cache_failure,
        :storage_failure
      ].freeze

      # (see ListenerInterface#handle)
      def handle(event, payload)
        return unless HONEYBADGER_EVENTS.include?(event)

        send(event, payload)
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
