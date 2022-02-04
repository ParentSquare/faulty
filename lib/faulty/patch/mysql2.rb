# frozen_string_literal: true

require 'mysql2'

if Gem::Version.new(Mysql2::VERSION) < Gem::Version.new('0.5.0')
  raise NotImplementedError, 'The faulty mysql2 patch requires mysql2 0.5.0 or later'
end

class Faulty
  module Patch
    # Patch Mysql2 to run connections and queries in a circuit
    #
    # This module is not required by default
    #
    # Pass a `:faulty` key into your MySQL connection options to enable
    # circuit protection. See {Patch.circuit_from_hash} for the available
    # options.
    #
    # COMMIT, ROLLBACK, and RELEASE SAVEPOINT queries are intentionally not
    # protected by the circuit. This is to allow open transactions to be closed
    # if possible.
    #
    # By default, all circuit errors raised by this patch inherit from
    # `::Mysql2::Error::ConnectionError`
    #
    # @example
    #   require 'faulty/patch/mysql2'
    #
    #   mysql = Mysql2::Client.new(host: '127.0.0.1', faulty: {})
    #   mysql.query('SELECT * FROM users') # raises Faulty::CircuitError if connection fails
    #
    #   # If the faulty key is not given, no circuit is used
    #   mysql = Mysql2::Client.new(host: '127.0.0.1')
    #   mysql.query('SELECT * FROM users') # not protected by a circuit
    #
    # @see Patch.circuit_from_hash
    module Mysql2
      include Base

      Patch.define_circuit_errors(self, ::Mysql2::Error::ConnectionError)

      QUERY_WHITELIST = [
        %r{\A(?:/\*.*?\*/)?\s*ROLLBACK}i,
        %r{\A(?:/\*.*?\*/)?\s*COMMIT}i,
        %r{\A(?:/\*.*?\*/)?\s*RELEASE\s+SAVEPOINT}i
      ].freeze

      def initialize(opts = {})
        @faulty_circuit = Patch.circuit_from_hash(
          'mysql2',
          opts[:faulty],
          errors: [
            ::Mysql2::Error::ConnectionError,
            ::Mysql2::Error::TimeoutError
          ],
          patched_error_mapper: Faulty::Patch::Mysql2
        )

        super
      end

      # Protect manual connection pings
      def ping
        faulty_run { super }
      rescue Faulty::Patch::Mysql2::FaultyError
        false
      end

      # Protect the initial connnection
      def connect(*args)
        faulty_run { super }
      end

      # Protect queries unless they are whitelisted
      def query(*args)
        return super if QUERY_WHITELIST.any? { |r| !r.match(args.first).nil? }

        faulty_run { super }
      end
    end
  end
end

module Mysql2
  class Client
    prepend(Faulty::Patch::Mysql2)
  end
end
