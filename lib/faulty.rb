# frozen_string_literal: true

require 'securerandom'
require 'forwardable'
require 'concurrent'

require 'faulty/deprecation'
require 'faulty/immutable_options'
require 'faulty/cache'
require 'faulty/circuit'
require 'faulty/error'
require 'faulty/events'
require 'faulty/patch'
require 'faulty/circuit_registry'
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

      @instances[name.to_s]
    end

    # Register an instance to the global Faulty state
    #
    # Will not replace an existing instance with the same name. Check the
    # return value if you need to know whether the instance already existed.
    #
    # @param name [Symbol] The name of the instance to register
    # @param instance [Faulty] The instance to register. If nil, a new instance
    #   will be created from the given options or block.
    # @param config [Hash] Attributes for {Faulty::Options}
    # @yield [Faulty::Options] For setting options in a block
    # @return [Faulty, nil] The previously-registered instance of that name if
    #   it already existed, otherwise nil.
    def register(name, instance = nil, **config, &block)
      raise UninitializedError unless @instances

      if instance
        raise ArgumentError, 'Do not give config options if an instance is given' if !config.empty? || block
      else
        instance = new(**config, &block)
      end

      @instances.put_if_absent(name.to_s, instance)
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
    # @see #list_circuits
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

    # Disable Faulty circuits
    #
    # This allows circuits to run as if they were always closed. Does
    # not disable caching.
    #
    # Intended for use in tests, or to disable Faulty entirely for an
    # environment.
    #
    # @return [void]
    def disable!
      @disabled = true
    end

    # Re-enable Faulty if disabled with {.disable!}
    #
    # @return [void]
    def enable!
      @disabled = false
    end

    # Check whether Faulty was disabled with {.disable!}
    #
    # @return [Boolean] True if disabled
    def disabled?
      @disabled == true
    end

    # Reset all circuits for the default instance
    #
    # @see #clear
    # @return [void]
    def clear!
      default.clear
    end
  end

  attr_reader :options

  # Options for {Faulty}
  #
  # @!attribute [r] cache
  #   @see Cache::AutoWire
  #   @return [Cache::Interface] A cache backend if you want
  #     to use Faulty's cache support. Automatically wrapped in a
  #     {Cache::AutoWire}. Default `Cache::AutoWire.new`.
  # @!attribute [r] circuit_defaults
  #   @see Circuit::Options
  #   @return [Hash] A hash of default options to be used when creating
  #     new circuits. See {Circuit::Options} for a full list.
  # @!attribute [r] storage
  #   @see Storage::AutoWire
  #   @return [Storage::Interface, Array<Storage::Interface>] The storage
  #   backend. Automatically wrapped in a {Storage::AutoWire}, so this can also
  #   be given an array of prioritized backends. Default `Storage::AutoWire.new`.
  # @!attribute [r] listeners
  #   @see Events::ListenerInterface
  #   @return [Array] listeners Faulty event listeners
  # @!attribute [r] notifier
  #   @return [Events::Notifier] A Faulty notifier. If given, listeners are
  #     ignored.
  Options = Struct.new(
    :cache,
    :circuit_defaults,
    :storage,
    :listeners,
    :notifier
  ) do
    include ImmutableOptions

    private

    def finalize
      self.notifier ||= Events::Notifier.new(listeners || [])
      self.storage = Storage::AutoWire.wrap(storage, notifier: notifier)
      self.cache = Cache::AutoWire.wrap(cache, notifier: notifier)
    end

    def required
      %i[cache circuit_defaults storage notifier]
    end

    def defaults
      {
        circuit_defaults: {},
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
    @options = Options.new(options, &block)
    @registry = CircuitRegistry.new(circuit_options)
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
    @registry.retrieve(name, options, &block)
  end

  # Get a list of all circuit names
  #
  # @return [Array<String>] The circuit names
  def list_circuits
    options.storage.list
  end

  # Reset all circuits
  #
  # Intended for use in tests. This can be expensive and is not appropriate
  # to call in production code
  #
  # See the documentation for your chosen backend for specific semantics and
  # safety concerns. For example, the Redis backend resets all circuits, but
  # it does not clear the circuit list to maintain thread-safety.
  #
  # @return [void]
  def clear!
    options.storage.clear
  end

  private

  # Get circuit options from the {Faulty} options
  #
  # @return [Hash] The circuit options
  def circuit_options
    @options.to_h
      .select { |k, _v| %i[cache storage notifier].include?(k) }
      .merge(options.circuit_defaults)
  end
end
