## Releae v0.8.2

* Fix crash for older versions of concurrent-ruby #42 justinhoward

## Releae v0.8.1

* Add cause message to CircuitTrippedError #40 justinhoward
* Record failures for cache hits #41 justinhoward


## Release v0.8.0

* Store circuit options in the backend when run #34 justinhoward

### Breaking Changes

* Added #get_options and #set_options to Faulty::Storage::Interface.
  These will need to be added to any custom backends
* Faulty::Storage::Interface#reset now requires removing options in
  addition to other stored values
* Circuit options will now be supplemented by stored options until they
  are run. This is technically a breaking change in behavior, although
  in most cases this should cause the expected result.
* Circuits are not memoized until they are run. Subsequent calls
  to Faulty#circuit can return different instances if the circuit is
  not run. However, once run, options are synchronized between
  instances, so likely this will not be a breaking change for most
  cases.

## Release v0.7.2

* Add Faulty.disable! for disabling globally #38 justinhoward
* Suppress circuit_success for proxy circuits #39 justinhoward

## Release v0.7.1

* Fix success event crash in log listener #37 justinhoward

## Release v0.7.0

* Add initial benchmarks and performance improvements #36 justinhoward

### Breaking Changes

The `circuit_success` event no longer contains the status value. Computing this
value was causing performance problems.

## Release v0.6.0

* docs, use correct state in description for skipped event #27 senny
* Fix CI to set REDIS_VERSION correctly #31 justinhoward
* Fix a potential memory leak in patches #32 justinhoward
* Capture an error for BUSY redis backend when patched #30 justinhoward
* Add a patch for mysql2 #28 justinhoward

## Release v0.5.1

* Fix Storage::FaultTolerantProxy to return empty history on entries fail #26 justinhoward

## Release v0.5.0

* Allow creating a new Faulty instance in Faulty#register #24 justinhoward
* Add support for patches to core dependencies starting with redis #14 justinhoward
* Improve storage #entries performance by returning entries #23 justinhoward

### Breaking Changes

* Faulty #[] no longer differentiates between symbols and strings when accessing
  Faulty instances
* Faulty::Storage::Interface must now return a history array instead of a
  circuit status object. Custom storage backends must be updated.

## Release v0.4.0

* Switch from Travis CI to GitHub actions #11 justinhoward
* Only run rubocop for Ruby 2.7 in CI #12 justinhoward
* Explicitly add support for Redis 3 and 4 #15 justinhoward
* Allow setting default circuit options on Faulty instances #16 justinhoward
* Switch to codacy for quality metrics #17 justinhoward
* Small logic fix to README #19 silasb
* Fix Redis storage dependency on ConnectionPool #21 justinhoward
* Allow passing custom circuit to AutoWire #22 justinhoward

### Breaking Changes

AutoWire.new is replaced with AutoWire.wrap and no longer creates an instance
of AutoWire.

## Release v0.3.0

* Add tools for backend fault-tolerance #10
  * CircuitProxy for wrapping storage in an internal circuit
  * FallbackChain storage backend for falling back to stable storage
  * Timeout warnings for Redis backend
  * AutoWire wrappers for automatically configuring storage and cache
  * Better documentation for fault-tolerance

## Release v0.2.0

* Remove Scopes and replace them with Faulty instances #9

### Breaking Changes

* `Faulty::Scope` has been removed. Use `Faulty.new` instead.
* `Faulty` is now a class, not a module

## Release v0.1.5

* Fix redis storage to expire state key when using CAS #8

## Release v0.1.4

* Improve spec coverage for supporting classes #6
* Fix redis bug where concurrent CAS requests could crash #7

## Release v0.1.3

* Fix bug where memory storage would delete the newest entries #5
* Add HoneybadgerListener for error reporting #4

## Release v0.1.2

* Fix Storage::FaultTolerantProxy open and reopen methods #2

## Release v0.1.1

* Fix a crash when Storage::FaultTolerantProxy created a status stub #1

## Release v0.1.0

Initial public release
