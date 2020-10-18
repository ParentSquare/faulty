# frozen_string_literal: true

class Faulty
  module Specs
    module Concurrency
      def concurrent_warmup(&block)
        @concurrent_warmup = block
      end

      def concurrently(times = 100, timeout: 3)
        barrier = Concurrent::CyclicBarrier.new(times)

        execute = lambda do
          @concurrent_warmup&.call
          barrier.wait(timeout)
          error = nil
          result = begin
            yield
          rescue StandardError => e
            error = e
          end

          barrier.wait(timeout)
          raise error if error

          result
        end

        threads = (0...(times - 1)).map do
          Thread.new do
            Thread.current.report_on_exception = false if Thread.current.respond_to?(:report_on_exception=)
            execute.call
          end
        end
        main_result = execute.call
        threads.map(&:value) + [main_result]
      end
    end
  end
end
