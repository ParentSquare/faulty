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
