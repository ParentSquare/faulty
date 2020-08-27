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
    attr_reader :options

    # Options for {Scope}
    #
    # @!attribute [r] cache
    #   @return [Cache::Interface] A cache backend if you want
    #     to use Faulty's cache support. Automatically wrapped in a
    #     {Cache::FaultTolerantProxy}. Default `Cache::Default.new`.
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
        self.notifier ||= Events::Notifier.new(listeners || [])

        self.storage ||= Storage::Memory.new
        unless storage.fault_tolerant?
          self.storage = Storage::FaultTolerantProxy.new(storage, notifier: notifier)
        end

        self.cache ||= Cache::Default.new
        unless cache.fault_tolerant?
          self.cache = Cache::FaultTolerantProxy.new(cache, notifier: notifier)
        end
      end

      def required
        %i[cache storage notifier]
      end

      def defaults
        {
          listeners: [Events::LogListener.new]
        }
      end
    end

    # Create a new Faulty Scope
    #
    # Note, the process of creating a new scope is not thread safe,
    # so make sure scopes are setup before spawning threads.
    #
    # @see Options
    # @param options [Hash] Attributes for {Options}
    # @yield [Options] For setting options in a block
    def initialize(**options, &block)
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
    # @param name [String] The name of the circuit
    # @param options [Hash] Attributes for {Circuit::Options}
    # @yield [Circuit::Options] For setting options in a block
    # @return [Circuit] The new circuit or the existing circuit if it already exists
    def circuit(name, **options, &block)
      name = name.to_s
      options = options.merge(circuit_options)
      @circuits.compute_if_absent(name) do
        Circuit.new(name, **options, &block)
      end
    end

    # Get a list of all circuit names
    #
    # @return [Array<String>] The circuit names
    def list_circuits
      options.storage.list
    end

    private

    # Get circuit options from the scope options
    #
    # @return [Hash] The circuit options
    def circuit_options
      options = @options.to_h
      options.delete(:listeners)
      options
    end
  end
end
