# frozen_string_literal: true

require 'redis'

class Faulty
  module Patch
    # Patch Redis to run all network IO in a circuit
    #
    # This module is not required by default
    #
    # Redis <= 4
    # ---------------------
    # Pass a `:faulty` key into your Redis connection options to enable
    # circuit protection. See {Patch.circuit_from_hash} for the available
    # options. On Redis 5+, the faulty key should be passed in the `:custom` hash
    # instead of the top-level options. See example.
    #
    # By default, all circuit errors raised by this patch inherit from
    # `::Redis::BaseConnectionError`
    #
    # @example
    #   require 'faulty/patch/redis'
    #
    #   # Redis <= 4
    #   redis = Redis.new(url: 'redis://localhost:6379', faulty: {})
    #   # Or for Redis 5+
    #   redis = Redis.new(url: 'redis://localhost:6379', custom: { faulty: {} })
    #
    #   redis.connect # raises Faulty::CircuitError if connection fails
    #
    #   # If the faulty key is not given, no circuit is used
    #   redis = Redis.new(url: 'redis://localhost:6379')
    #   redis.connect # not protected by a circuit
    #
    # @see Patch.circuit_from_hash
    module Redis
    end
  end
end

if Redis::VERSION.to_f < 5
  require 'faulty/patch/redis/patch'
else
  require 'faulty/patch/redis/middleware'
end
