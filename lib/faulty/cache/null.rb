# frozen_string_literal: true

module Faulty
  module Cache
    class Null
      def read(_key)
      end

      def write(_key, _value, expires_in: nil)
      end

      def fault_tolerant?
        true
      end
    end
  end
end
