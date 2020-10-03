# frozen_string_literal: true

class Faulty
  # The namespace for Faulty storage
  module Storage
  end
end

require 'faulty/storage/auto_wire'
require 'faulty/storage/circuit_proxy'
require 'faulty/storage/fallback_chain'
require 'faulty/storage/fault_tolerant_proxy'
require 'faulty/storage/memory'
require 'faulty/storage/redis'
