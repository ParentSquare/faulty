# frozen_string_literal: true

require 'faulty/storage/interface'

# Conformance test for {Faulty::Storage::Interface}.
#
# Every concrete storage backend (and every wrapper that pretends to be one)
# MUST implement every public instance method declared on the documentation
# interface. This is the structural guard that prevents a future addition to
# `Storage::Interface` from silently regressing wrappers like `CircuitProxy`
# or `FallbackChain` that don't use `method_missing` or `Forwardable` for the
# full surface.
RSpec.describe Faulty::Storage::Interface do
  interface_methods = described_class.public_instance_methods(false).sort

  storage_classes = [
    Faulty::Storage::Memory,
    Faulty::Storage::Redis,
    Faulty::Storage::Null,
    Faulty::Storage::FallbackChain,
    Faulty::Storage::FaultTolerantProxy,
    Faulty::Storage::CircuitProxy
  ]

  storage_classes.each do |klass|
    describe klass do
      interface_methods.each do |method|
        it "implements ##{method}" do
          expect(klass.public_method_defined?(method)).to be(true),
            "#{klass} is missing public method ##{method} required by Faulty::Storage::Interface"
        end
      end
    end
  end
end
