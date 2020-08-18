# frozen_string_literal: true

module Faulty
  class Result
    NOTHING = {}.freeze

    def initialize(ok: NOTHING, error: NOTHING) # rubocop:disable Naming/MethodParameterName
      raise 'Result must have an ok or error value' if ok.eql?(NOTHING) && error.eql?(NOTHING)
      raise 'Result must not have both an ok and error value' if !ok.eql?(NOTHING) && !error.eql?(NOTHING)

      @ok = ok
      @error = error
      @checked = false
    end

    def ok?
      @checked = true
      ok_unchecked?
    end

    def error?
      !ok?
    end

    def get
      validate_checked!
      raise 'Result: Tried to get value for error result' unless ok?

      @ok
    end

    def error
      validate_checked!
      raise 'Result: Tried to get error for ok result' unless error?

      @ok
    end

    def fetch(default = nil)
      if ok_unchecked?
        @ok
      elsif block_given?
        yield @error
      else
        default
      end
    end

    private

    def ok_unchecked?
      !@ok.eql?(NOTHING)
    end

    def validate_checked!
      raise 'Result: Called get without checking ok? or error?' unless @checked
    end
  end
end
