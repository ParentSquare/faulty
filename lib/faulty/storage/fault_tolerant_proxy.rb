# frozen_string_literal: true

module Faulty
  module Storage
    class FaultTolerantProxy
      attr_reader :options

      Options = Struct.new(
        :notifier
      ) do
        include ImmutableOptions

        private

        def required
          %i[notifier]
        end
      end

      def initialize(storage, **options, &block)
        @storage = storage
        @options = Options.new(options, &block)
      end

      def entry(circuit, time, success)
        @storage.entry(circuit, time, success)
      rescue StandardError => e
        options.notifier.notify(:storage_failure, circuit: circuit, action: :entry, error: e)
        stub_status(circuit)
      end

      def open(circuit)
        @storage.open(circuit)
      rescue StandardError => e
        options.notifier.notify(:storage_failure, circuit: circuit, action: :open, error: e)
        false
      end

      def reopen(circuit)
        @storage.reopen(circuit)
      rescue StandardError => e
        options.notifier.notify(:storage_failure, circuit: circuit, action: :reopen, error: e)
        false
      end

      def close(circuit)
        @storage.close(circuit)
      rescue StandardError => e
        options.notifier.notify(:storage_failure, circuit: circuit, action: :close, error: e)
        false
      end

      def lock(circuit, state)
        @storage.lock(circuit, state)
      end

      def unlock(circuit)
        @storage.unlock(circuit)
      end

      def reset(circuit)
        @storage.reset(circuit)
      end

      def status(circuit)
        @storage.status(circuit)
      rescue StandardError => e
        options.notifier.notify(:storage_failure, circuit: circuit, action: :status, error: e)
        stub_status(circuit)
      end

      def history(circuit)
        @storage.history(circuit)
      end

      # This cache makes any storage fault tolerant, so this is always `true`
      #
      # @return [true]
      def fault_tolerant?
        true
      end

      private

      def stub_status(circuit)
        Faulty::Status.new(
          cool_down: circuit.options.cool_down,
          stub: true,
          sample_threshold: circuit.options.sample_threshold,
          rate_threshold: circuit.options.rate_threshold
        )
      end
    end
  end
end
