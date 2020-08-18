# frozen_string_literal: true

module Faulty
  module Events
    class LogListener
      attr_reader :logger

      def initialize(logger = nil)
        logger ||= defined?(Rails) ? Rails.logger : Logger.new($stderr)
        @logger = logger
      end

      def handle(event, payload)
        return unless EVENTS.include?(event)

        public_send(event, payload)
      end

      def circuit_success(payload)
        logger.debug("Circuit succeeded: #{payload[:circuit].name}=#{payload[:status].state}")
      end

      def circuit_failure(payload)
        logger.debug("Circuit failed: #{payload[:circuit].name}=#{payload[:status].state}: #{payload[:error].message}")
      end

      def circuit_skipped(payload)
        logger.debug("Circuit skipped: #{payload[:circuit].name}")
      end

      def circuit_opened(payload)
        logger.debug("Circuit opened: #{payload[:circuit].name}: #{payload[:error].message}")
      end

      def circuit_closed(payload)
        logger.debug("Circuit closed: #{payload[:circuit].name}")
      end

      def cache_failure(payload)
        logger.debug("Cache Failure: #{payload[:action]}(#{payload[:key]}): #{payload[:error]}")
      end

      def storage_failure(payload)
        logger.debug("Storage Failure: #{payload[:action]}(#{payload[:circuit].name}): #{payload[:error]}")
      end
    end
  end
end
