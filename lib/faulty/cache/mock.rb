# frozen_string_literal: true

module Faulty
  module Cache
    class Mock
      def initialize
        @cache = {}
        @expires = {}
      end

      def read(key)
        return if @expires[key] && @expires[key] < Faulty.current_time

        @cache[key]
      end

      def write(key, value, expires_in: nil)
        @cache[key] = value
        @expires[key] = Faulty.current_time + expires_in unless expires_in.nil?
      end

      def fault_tolerant?
        true
      end
    end
  end
end
