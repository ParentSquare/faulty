# frozen_string_literal: true

require 'faulty/patch/base'

class Faulty
  # Automatic wrappers for common core dependencies like database connections
  # or caches
  module Patch
    class << self
      # Create a circuit from a configuration hash
      #
      # This is intended to be used in contexts where the user passes in
      # something like a connection hash to a third-party library. For example
      # the Redis patch hooks into the normal Redis connection options to add
      # a `:faulty` key, which is a hash of faulty circuit options. This is
      # slightly different from the normal Faulty circuit options because
      # we also accept an `:instance` key which is a faulty instance.
      #
      # @example
      #   # We pass in a faulty instance along with some circuit options
      #   Patch.circuit_from_hash(
      #     :mysql,
      #     { host: 'localhost', faulty: {
      #       name: 'my_mysql', # A custom circuit name can be included
      #       instance: Faulty.new,
      #       sample_threshold: 5
      #       }
      #     }
      #   )
      #
      # @example
      #   # instance can be a registered faulty instance referenced by a string
      #   or symbol
      #   Faulty.register(:db_faulty, Faulty.new)
      #   Patch.circuit_from_hash(
      #     :mysql,
      #     { host: 'localhost', faulty: { instance: :db_faulty } }
      #   )
      # @example
      #   # If instance is a hash with the key :constant, the value can be
      #   # a global constant name containing a Faulty instance
      #   DB_FAULTY = Faulty.new
      #   Patch.circuit_from_hash(
      #     :mysql,
      #     { host: 'localhost', faulty: { instance: { constant: 'DB_FAULTY' } } }
      #   )
      #
      # @example
      #   # Certain patches may want to enforce certain options like :errors
      #   # This can be done via hash or the usual block syntax
      #   Patch.circuit_from_hash(:mysql,
      #     { host: 'localhost', faulty: {} }
      #     errors: [Mysql2::Error]
      #   )
      #
      #   Patch.circuit_from_hash(:mysql,
      #     { host: 'localhost', faulty: {} }
      #   ) do |conf|
      #     conf.errors = [Mysql2::Error]
      #   end
      #
      # @param default_name [String] The default name for the circuit
      # @param hash [Hash] A hash of user-provided options. Supports any circuit
      #   option and these additional options
      # @option hash [String] :name The circuit name. Defaults to `default_name`
      # @option hash [Boolean] :patch_errors By default, circuit errors will be
      #   subclasses of `options[:patched_error_module]`. The user can disable
      #   this by setting this option to false.
      # @option hash [Faulty, String, Symbol, Hash{ constant: String }] :instance
      #   A reference to a faulty instance. See examples.
      # @param options [Hash] Additional override options. Supports any circuit
      #   option and these additional ones.
      # @option options [Module] :patched_error_module The namespace module
      #   for patched errors
      # @yield [Circuit::Options] For setting override options in a block
      # @return [Circuit, nil] The circuit if one was created
      def circuit_from_hash(default_name, hash, **options, &block)
        return unless hash

        hash = symbolize_keys(hash)
        name = hash.delete(:name) || default_name
        patch_errors = hash.delete(:patch_errors) != false
        error_module = options.delete(:patched_error_module)
        hash[:error_module] ||= error_module if error_module && patch_errors
        faulty = resolve_instance(hash.delete(:instance))
        faulty.circuit(name, **hash, **options, &block)
      end

      # Create a full set of {CircuitError}s with a given base error class
      #
      # For patches that need their errors to be subclasses of a common base.
      #
      # @param namespace [Module] The module to define the error classes in
      # @param base [Class] The base class for the error classes
      # @return [void]
      def define_circuit_errors(namespace, base)
        circuit_error = Class.new(base) { include CircuitErrorBase }
        namespace.const_set('CircuitError', circuit_error)
        namespace.const_set('OpenCircuitError', Class.new(circuit_error))
        namespace.const_set('CircuitFailureError', Class.new(circuit_error))
        namespace.const_set('CircuitTrippedError', Class.new(circuit_error))
      end

      private

      # Resolves a constant from a constant name or returns a default
      #
      # - If value is a string or symbol, gets a registered Faulty instance with that name
      # - If value is a Hash with a key `:constant`, resolves the value to a global constant
      # - If value is nil, gets Faulty.default
      # - Otherwise, return value directly
      #
      # @param value [String, Symbol, Faulty, nil] The object or constant name to resolve
      # @return [Object] The resolved Faulty instance
      def resolve_instance(value)
        case value
        when String, Symbol
          result = Faulty[value]
          raise NameError, "No Faulty instance for #{value}" unless result

          result
        when Hash
          const_name = value[:constant]
          raise ArgumentError 'Missing hash key :constant for Faulty instance' unless const_name

          Kernel.const_get(const_name)
        when nil
          Faulty.default
        else
          value
        end
      end

      # Some config files may not suport symbol keys, so we convert the hash
      # to use symbols so that users can pass in strings
      #
      # We cannot use transform_keys since we support Ruby < 2.5
      #
      # @param hash [Hash] A hash to convert
      # @return [Hash] The hash with keys as symbols
      def symbolize_keys(hash)
        result = {}
        hash.each do |key, val|
          result[key.to_sym] = if val.is_a?(Hash)
            symbolize_keys(val)
          else
            val
          end
        end
        result
      end
    end
  end
end
