# frozen_string_literal: true

class Faulty
  module Patch
    module Redis
      Patch.define_circuit_errors(self, ::RedisClient::ConnectionError)

      class BusyError < ::RedisClient::CommandError
      end

      module Middleware
        include Base

        def initialize(client)
          @faulty_circuit = Patch.circuit_from_hash(
            'redis',
            client.config.custom[:faulty],
            errors: [
              ::RedisClient::ConnectionError,
              BusyError
            ],
            patched_error_mapper: Faulty::Patch::Redis
          )

          super
        end

        def connect(redis_config)
          faulty_run { super }
        end

        def call(commands, redis_config)
          faulty_run { wrap_command { super } }
        end

        def call_pipelined(commands, redis_config)
          faulty_run { wrap_command { super } }
        end

        private

        def wrap_command
          yield
        rescue ::RedisClient::CommandError => e
          raise BusyError, e.message if e.message.start_with?('BUSY')

          raise
        end
      end

      ::RedisClient.register(Middleware)
    end
  end
end
