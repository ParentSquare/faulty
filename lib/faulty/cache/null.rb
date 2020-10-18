# frozen_string_literal: true

class Faulty
  module Cache
    # A cache backend that does nothing
    #
    # All methods are stubs and do no caching
    class Null
      # @return [nil]
      def read(_key)
      end

      # @return [void]
      def write(_key, _value, expires_in: nil)
      end

      # @return [true]
      def fault_tolerant?
        true
      end
    end
  end
end
