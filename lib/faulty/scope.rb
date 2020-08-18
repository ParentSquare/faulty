# frozen_string_literal: true

module Faulty
  # A {Scope} is a group of options and circuits
  #
  # For most use-cases the default scope should be used, however, it's possible
  # to create any number of scopes for applications that require a more complex
  # configuration or for testing.
  #
  # For the most part, scopes are independent, however for some cache and
  # storage backends, you will need to ensure that the cache keys and circuit
  # names don't overlap between scopes. For example, if using the Redis storage
  # backend, you should specify different key prefixes for each scope.
  class Scope
    attr_reader :name
    attr_reader :options

    # @!attribute [r] cache
    #   @return [Cache::Interface] A cache backend if you want
    #     to use Faulty's cache support. Automatically wrapped in a
    #     {Cache::FaultTolerantProxy}. Default `nil`.
    # @!attribute [r] storage
    #   @return [Storage::Interface] The storage backend.
    #     Automatically wrapped in a {Storage::FaultTolerantProxy}.
    #     Default `Storage::Memory.new`.
    # @!attribute [r] listeners
    #   @return [Array] listeners Faulty event listeners
    # @!attribute [r] notifier
    #   @return [Events::Notifier] A Faulty notifier. If given, listeners are
    #     ignored.
    Options = Struct.new(
      :cache,
      :storage,
      :listeners,
      :notifier
    ) do
      include ImmutableOptions

      private

      def finalize
        self.listeners ||= [Events::LogListener.new]
        self.notifier ||= Events::Notifier.new(listeners || [])

        unless storage.is_a?(Storage::FaultTolerantProxy)
          self.storage ||= Storage::Memory.new
          self.storage = Storage::FaultTolerantProxy.new(
            storage,
            notifier: notifier
          )
        end

        if cache && !cache.is_a?(Cache::FaultTolerantProxy)
          self.cache = Cache::FaultTolerantProxy.new(
            cache,
            notifier: notifier
          )
        end
      end

      def required
        %i[storage notifier]
      end
    end

    # Create a new Faulty Scope
    #
    # @see Options
    # @param name [Symbol, String] The name of the scope
    # @param options [Hash] Attributes for {Options}
    # @yield [Options] For setting options in a block
    def initialize(name, **options, &block)
      @name = name
      @circuits = Concurrent::Map.new
      @options = Options.new(options, &block)
    end

    # Create or retrieve a circuit
    #
    # Within a scope, circuit instances have unique names, so if the given circuit
    # name already exists, then the existing circuit will be returned, otherwise
    # a new circuit will be created. If an existing circuit is returned, then
    # the {options} param and block are ignored.
    #
    # @param (see Circuit#initialize)
    # @yield (see Circuit#initialize)
    # @return [Circuit] The new circuit or the existing circuit if it already exists
    def circuit(name, **options, &block)
      options = options.merge(circuit_options)
      @circuits.compute_if_absent(name) do
        Circuit.new(name, **options, &block)
      end
    end

    private

    def circuit_options
      options = @options.to_h
      options.delete(:listeners)
      options
    end
  end
end
