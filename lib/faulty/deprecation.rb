# frozen_string_literal: true

class Faulty
  # Support deprecating Faulty features
  module Deprecation
    class << self
      # Call to raise errors instead of logging warnings for Faulty deprecations
      def raise_errors!(enabled = true)
        @raise_errors = (enabled == true)
      end

      def silenced
        @silence = true
        yield
      ensure
        @silence = false
      end

      # @private
      def method(klass, name, note: nil, sunset: nil)
        deprecate("#{klass}##{name}", note: note, sunset: sunset)
      end

      # @private
      def deprecate(subject, note: nil, sunset: nil)
        return if @silence

        message = "#{subject} is deprecated"
        message += " and will be removed in #{sunset}" if sunset
        message += " (#{note})" if note
        raise DeprecationError, message if @raise_errors

        Kernel.warn("DEPRECATION: #{message}")
      end
    end
  end
end
