# frozen_string_literal: true

require 'securerandom'
require 'concurrent-ruby'

require 'faulty/immutable_options'
require 'faulty/cache/default'
require 'faulty/cache/fault_tolerant_proxy'
require 'faulty/cache/mock'
require 'faulty/cache/null'
require 'faulty/cache/rails'
require 'faulty/circuit'
require 'faulty/error'
require 'faulty/events'
require 'faulty/events/callback_listener'
require 'faulty/events/notifier'
require 'faulty/events/log_listener'
require 'faulty/result'
require 'faulty/scope'
require 'faulty/status'
require 'faulty/storage/fault_tolerant_proxy'
require 'faulty/storage/memory'
require 'faulty/storage/redis'

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
    # @param scope_name [Symbol] The scope to create. Can be set to nil to skip
    #   creating a scope during init.
    # @param (see Scope#initialize)
    # @yield (see Scope#initialize)
    # @return [self]
    def init(scope_name = :default, **config, &block)
      raise "#{self} already initialized" if @scopes

      @scopes = Concurrent::Map.new
      register(scope_name, Scope.new(**config, &block)) unless scope_name.nil?
      self
    end

    # Get the default scope
    #
    # @return [Scope, nil] The default scope if it is registered
    def default
      self[:default]
    end

    # Get a scope by name
    #
    # @return [Scope, nil] The named scope if it is registered
    def [](scope_name)
      raise 'Faulty is not initialized' unless @scopes

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
      raise 'Faulty is not initialized' unless @scopes

      @scopes.put_if_absent(name, scope)
    end

    # Get or create a circuit for the default scope
    #
    # @raise RuntimeError If the default scope has not been created
    # @param (see Scope#circuit)
    # @yield (see Scope#circuit)
    # @return (see Scope#circuit)
    def circuit(name, **config, &block)
      scope = default
      raise 'No default scope. Create one or get your scope with Faulty[:scope_name]' unless scope

      scope.circuit(name, **config, &block)
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
