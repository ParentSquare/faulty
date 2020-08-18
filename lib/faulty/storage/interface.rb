# frozen_string_literal: true

module Faulty
  module Storage
    class Interface
      # @return [Status]
      def entry(circuit, time, success)
        raise NotImplementedError
      end

      # @return [Boolean] True if the circuit transitioned from closed to open
      def open(circuit)
        raise NotImplementedError
      end

      # @return [Boolean] True if the circuit transitioned from open to closed
      def close(circuit)
        raise NotImplementedError
      end

      def lock(circuit, state)
        raise NotImplementedError
      end

      def unlock(circuit)
        raise NotImplementedError
      end

      def reset(circuit)
        raise NotImplementedError
      end

      def status(circuit)
        raise NotImplementedError
      end

      def history(circuit)
        raise NotImplementedError
      end
    end
  end
end
