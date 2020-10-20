# frozen_string_literal: true

require 'securerandom'
require 'concurrent-ruby'

require 'faulty/immutable_options'
require 'faulty/circuit_delegator'
require 'faulty/cache'
require 'faulty/circuit'
require 'faulty/error'
require 'faulty/events'
require 'faulty/result'
require 'faulty/status'
require 'faulty/storage'

# The {Faulty} class has class-level methods for global state or can be
# instantiated to create an independent configuration.
#
# If you are using global state, call {Faulty#init} during your application's
# initialization. This is the simplest way to use {Faulty}. If you prefer, you
# can also call {Faulty.new} to create independent {Faulty} instances.
class Faulty
  class << self
    # Start the Faulty environment
    #
    # This creates a global shared Faulty state for configuration and for
    # re-using State objects.
    #
    # Not thread safe, should be executed before any worker threads
    # are spawned.
    #
    # If you prefer dependency-injection instead of global state, you can skip
    # `init` and use {Faulty.new} to pass an instance directoy to your
    # dependencies.
    #
    # @param default_name [Symbol] The name of the default instance. Can be set
    # to `nil` to skip creating a default instance.
    # @param config [Hash] Attributes for {Faulty::Options}
    # @yield [Faulty::Options] For setting options in a block
    # @return [self]
    def init(default_name = :default, **config, &block)
      raise AlreadyInitializedError if @instances

      @default_instance = default_name
      @instances = Concurrent::Map.new
      register(default_name, new(**config, &block)) unless default_name.nil?
      self
    rescue StandardError
      @instances = nil
      raise
    end

    # Get the default instance given during {.init}
    #
    # @return [Faulty, nil] The default instance if it is registered
    def default
      raise UninitializedError unless @instances
      raise MissingDefaultInstanceError unless @default_instance

      self[@default_instance]
    end

    # Get an instance by name
    #
    # @return [Faulty, nil] The named instance if it is registered
    def [](name)
      raise UninitializedError unless @instances

      @instances[name]
    end

    # Register an instance to the global Faulty state
    #
    # Will not replace an existing instance with the same name. Check the
    # return value if you need to know whether the instance already existed.
    #
    # @param name [Symbol] The name of the instance to register
    # @param instance [Faulty] The instance to register
    # @return [Faulty, nil] The previously-registered instance of that name if
    #   it already existed, otherwise nil.
    def register(name, instance)
      raise UninitializedError unless @instances

      @instances.put_if_absent(name, instance)
    end

    # Get the options for the default instance
    #
    # @raise MissingDefaultInstanceError If the default instance has not been created
    # @return [Faulty::Options]
    def options
      default.options
    end

    # Get or create a circuit for the default instance
    #
    # @raise UninitializedError If the default instance has not been created
    # @param (see Faulty#circuit)
    # @yield (see Faulty#circuit)
    # @return (see Faulty#circuit)
    def circuit(name, **config, &block)
      default.circuit(name, **config, &block)
    end

    # Get a list of all circuit names for the default instance
    #
    # @return [Array<String>] The circuit names
    def list_circuits
      options.storage.list
    end

    # The current time
    #
    # Used by Faulty wherever the current time is needed. Can be overridden
    # for testing
    #
    # @return [Time] The current time
    def current_time
      Time.now.to_i
    end
  end

  attr_reader :options

  # Options for {Faulty}
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

  # Create a new {Faulty} instance
  #
  # Note, the process of creating a new instance is not thread safe,
  # so make sure instances are setup during your application's initialization
  # phase.
  #
  # For the most part, {Faulty} instances are independent, however for some
  # cache and storage backends, you will need to ensure that the cache keys
  # and circuit names don't overlap between instances. For example, if using the
  # {Storage::Redis} storage backend, you should specify different key
  # prefixes for each instance.
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
  # Within an instance, circuit instances have unique names, so if the given circuit
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

  # Get circuit options from the {Faulty} options
  #
  # @return [Hash] The circuit options
  def circuit_options
    options = @options.to_h
    options.delete(:listeners)
    options
  end
end
