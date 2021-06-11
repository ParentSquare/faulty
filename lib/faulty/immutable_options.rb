# frozen_string_literal: true

class Faulty
  # A struct that cannot be modified after initialization
  module ImmutableOptions
    # @param hash [Hash] A hash of attributes to initialize with
    # @yield [self] Yields itself to the block to set options before freezing
    def initialize(hash, &block)
      setup(defaults.merge(hash), &block)
    end

    def dup_with(hash, &block)
      dup.setup(hash, &block)
    end

    def setup(hash)
      hash&.each { |key, value| self[key] = value }
      yield self if block_given?
      finalize
      guard_required!
      freeze
      self
    end

    # A hash of default values to set before yielding to the block
    #
    # @return [Hash<Symbol, Object>]
    def defaults
      {}
    end

    # An array of required attributes
    #
    # @return [Array<Symbol>]
    def required
      []
    end

    # Runs before freezing to finalize attribute initialization
    #
    # @return [void]
    def finalize
    end

    private

    # Raise an error if required options are missing
    def guard_required!
      required.each do |key|
        raise ArgumentError, "Missing required attribute #{key}" if self[key].nil?
      end
    end
  end
end
