# frozen_string_literal: true

require 'pg'

class Faulty
  module Patch
    # Patch for the Postgres gem
    module Postgres
      include Base

      Patch.define_circuit_errors(self, ::PG::ConnectionBad)

      QUERY_WHITELIST = [
        %r{\A(?:/\*.*?\*/)?\s*ROLLBACK}i,
        %r{\A(?:/\*.*?\*/)?\s*COMMIT}i,
        %r{\A(?:/\*.*?\*/)?\s*RELEASE\s+SAVEPOINT}i
      ].freeze

      def initialize(opts = {})
        @faulty_circuit = Patch.circuit_from_hash(
          'pg',
          opts[:faulty],
          errors: [
            ::PG::ConnectionBad,
            ::PG::UnableToSend
          ],
          patched_error_mapper: Faulty::Patch::Postgres
        )

        super
      end

      def ping
        faulty_run { super }
      rescue Faulty::Patch::Postgres::FaultyError
        false
      end

      def connect(*args)
        faulty_run { super }
      end

      def query(*args)
        return super if QUERY_WHITELIST.any? { |r| !r.match(args.first).nil? }

        faulty_run { super }
      end
    end
  end
end

module PG
  class Connection
    prepend Faulty::Patch::Postgres
  end
end
