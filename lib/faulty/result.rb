# frozen_string_literal: true

class Faulty
  # An approximation of the `Result` type from some strongly-typed languages.
  #
  # F#: https://docs.microsoft.com/en-us/dotnet/fsharp/language-reference/results
  #
  # Rust: https://doc.rust-lang.org/std/result/enum.Result.html
  #
  # Since we can't enforce the type at compile-time, we use runtime errors to
  # check the result for consistency as early as possible. This means we
  # enforce runtime checks of the result type. This approach does not eliminate
  # issues, but it does help remind the user to check the result in most cases.
  #
  # This is returned from {Circuit#try_run} to allow error handling without
  # needing to rescue from errors.
  #
  # @example
  #   result = Result.new(ok: 'foo')
  #
  #   # Check the result before calling get
  #   if result.ok?
  #     puts result.get
  #   else
  #     puts result.error.message
  #   end
  #
  # @example
  #   result = Result.new(error: StandardError.new)
  #   puts result.or_default('fallback') # prints "fallback"
  #
  # @example
  #   result = Result.new(ok: 'foo')
  #   result.get # raises UncheckedResultError
  #
  # @example
  #   result = Result.new(ok: 'foo')
  #   if result.ok?
  #     result.error.message # raises WrongResultError
  #   end
  class Result
    # The constant used to designate that a value is empty
    #
    # This is needed to differentiate between an ok `nil` value and
    # an empty value.
    #
    # @private
    NOTHING = {}.freeze

    # Create a new `Result` with either an ok or error value
    #
    # Exactly one parameter must be given, and not both.
    #
    # @param ok An ok value
    # @param error [Error] An error instance
    def initialize(ok: NOTHING, error: NOTHING)
      if ok.equal?(NOTHING) && error.equal?(NOTHING)
        raise ArgumentError, 'Result must have an ok or error value'
      end
      if !ok.equal?(NOTHING) && !error.equal?(NOTHING)
        raise ArgumentError, 'Result must not have both an ok and error value'
      end

      @ok = ok
      @error = error
      @checked = false
    end

    # Check if the value is an ok value
    #
    # @return [Boolean] True if this result is ok
    def ok?
      @checked = true
      ok_unchecked?
    end

    # Check if the value is an error value
    #
    # @return [Boolean] True if this result is an error
    def error?
      !ok?
    end

    # Get the ok value
    #
    # @raise UncheckedResultError if this result was not checked using {#ok?} or {#error?}
    # @raise WrongResultError if this result is an error
    # @return The ok value
    def get
      validate_checked!('get')
      unsafe_get
    end

    # Get the ok value without checking whether it's safe to do so
    #
    # @raise WrongResultError if this result is an error
    # @return The ok value
    def unsafe_get
      raise WrongResultError, 'Tried to get value for error result' unless ok_unchecked?

      @ok
    end

    # Get the error value
    #
    # @raise UncheckedResultError if this result was not checked using {#ok?} or {#error?}
    # @raise WrongResultError if this result is ok
    def error
      validate_checked!('error')
      unsafe_error
    end

    # Get the error value without checking whether it's safe to do so
    #
    # @raise WrongResultError if this result is ok
    # @return [Error] The error
    def unsafe_error
      raise WrongResultError, 'Tried to get error for ok result' if ok_unchecked?

      @error
    end

    # Get the ok value if this result is ok, otherwise return a default
    #
    # @param default The default value. Ignored if a block is given
    # @yield A block returning the default value
    # @return The ok value or the default if this result is an error
    def or_default(default = nil)
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
      !@ok.equal?(NOTHING)
    end

    def validate_checked!(method)
      unless @checked
        raise UncheckedResultError, "Result: Called #{method} without checking ok? or error?"
      end
    end
  end
end
