# frozen_string_literal: true

class Faulty
  # The namespace for Faulty storage
  module Storage
  end
end

require 'faulty/storage/fault_tolerant_proxy'
require 'faulty/storage/memory'
require 'faulty/storage/redis'
