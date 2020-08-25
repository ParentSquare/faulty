# frozen_string_literal: true

module Faulty
  module Cache
    class Default
      def initialize
        @cache = if defined?(::Rails)
          Cache::Rails.new(::Rails.cache)
        elsif defined?(::ActiveSupport::Cache::MemoryStore)
          Cache::Rails.new(ActiveSupport::Cache::MemoryStore.new)
        else
          Cache::Null.new
        end
      end

      def read(key)
        @cache.read(key)
      end

      def write(key, value, expires_in: nil)
        @cache.write(key, value, expires_in: expires_in)
      end

      def fault_tolerant?
        @cache.fault_tolerant?
      end
    end
  end
end
