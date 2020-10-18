# frozen_string_literal: true

class Faulty
  # A struct that cannot be modified after initialization
  module ImmutableOptions
    # @param hash [Hash] A hash of attributes to initialize with
    # @yield [self] Yields itself to the block to set options before freezing
    def initialize(hash)
      defaults.merge(hash).each { |key, value| self[key] = value }
      yield self if block_given?
      finalize
      required.each do |key|
        raise ArgumentError, "Missing required attribute #{key}" if self[key].nil?
      end
      freeze
    end

    private

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
  end
end
