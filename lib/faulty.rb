# frozen_string_literal: true

require 'securerandom'
require 'concurrent-ruby'

require 'faulty/immutable_options'
require 'faulty/cache'
require 'faulty/circuit'
require 'faulty/error'
require 'faulty/events'
require 'faulty/result'
require 'faulty/scope'
require 'faulty/status'
require 'faulty/storage'

# The top-level namespace for Faulty
#
# Fault-tolerance tools for ruby based on circuit-breakers
module Faulty
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
    # init and pass a {Scope} directly to your dependencies.
    #
    # @param scope_name [Symbol] The name of the default scope. Can be set to
    #   `nil` to skip creating a default scope.
    # @param config [Hash] Attributes for {Scope::Options}
    # @yield [Scope::Options] For setting options in a block
    # @return [self]
    def init(scope_name = :default, **config, &block)
      raise AlreadyInitializedError if @scopes

      @default_scope = scope_name
      @scopes = Concurrent::Map.new
      register(scope_name, Scope.new(**config, &block)) unless scope_name.nil?
      self
    rescue StandardError
      @scopes = nil
      raise
    end

    # Get the default scope given during {.init}
    #
    # @return [Scope, nil] The default scope if it is registered
    def default
      raise MissingDefaultScopeError unless @default_scope

      self[@default_scope]
    end

    # Get a scope by name
    #
    # @return [Scope, nil] The named scope if it is registered
    def [](scope_name)
      raise UninitializedError unless @scopes

      @scopes[scope_name]
    end

    # Register a scope to the global Faulty state
    #
    # Will not replace an existing scope with the same name. Check the
    # return value if you need to know whether the scope already existed.
    #
    # @param name [Symbol] The name of the scope to register
    # @param scope [Scope] The scope to register
    # @return [Scope, nil] The previously-registered scope of that name if
    #   it already existed, otherwise nil.
    def register(name, scope)
      raise UninitializedError unless @scopes

      @scopes.put_if_absent(name, scope)
    end

    # Get the options for the default scope
    #
    # @raise MissingDefaultScopeError If the default scope has not been created
    # @return [Scope::Options]
    def options
      default.options
    end

    # Get or create a circuit for the default scope
    #
    # @raise UninitializedError If the default scope has not been created
    # @param (see Scope#circuit)
    # @yield (see Scope#circuit)
    # @return (see Scope#circuit)
    def circuit(name, **config, &block)
      default.circuit(name, **config, &block)
    end

    # Get a list of all circuit names for the default scope
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
end
