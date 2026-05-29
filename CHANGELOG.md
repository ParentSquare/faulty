Changelog
===================

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

[Unreleased]
-------------------

[0.13.1] - 2026-05-29
---------------------

### Fixed

* `Cache::AutoWire.wrap` now applies `CircuitProxy` and `FaultTolerantProxy`
  to `Cache::Default` when the resolved backend is not fault tolerant (e.g.
  `Rails.cache`). Previously a `nil` cache short-circuited the wrapping and
  could leave the auto-wired cache non-fault-tolerant. justinhoward

[0.13.0] - 2026-05-13
---------------------

### Added

* Reserve half-open test runs across processes so only one process executes
  the test block when a circuit becomes half-open. justinhoward

### Changed

* `Faulty::Status` now captures `current_time` once when the status is built,
  so all predicates (`open?`, `half_open?`, `reserved?`) reason about the same
  point in time. Previously each predicate called `Faulty.current_time`
  independently. justinhoward
* `Storage::Redis#close` now also clears the `reserved_at` key. justinhoward

### Fixed

* `Storage::Redis#reserve` uses safe navigation when serializing
  `previous_reserved_at` for `WATCH`, so the very first CAS against a missing
  key compares correctly. justinhoward
* `Storage::Redis#reset` now clears the `reserved_at` key. justinhoward
* `Status#can_run?` now treats `locked_closed?` as an unconditional override,
  so a manually locked-closed circuit runs even when a half-open reservation
  is still in effect from a prior cycle. justinhoward

### Breaking Changes

* `Storage::Interface` adds a required `#reserve(circuit, reserved_at,
  previous_reserved_at)` method. Custom storage backends must implement it,
  and the `Status` value object must carry the new `reserved_at` attribute.
  See `Storage::Interface#reserve` for the contract and the conformance
  test in `spec/storage/interface_spec.rb` for the structural guarantee.

[0.12.0] - 2026-05-13
---------------------

Runtime behavior is unchanged from `0.11.0` — the version bump reflects
support-policy and toolchain breaking changes only. Upgrading should be
a drop-in replacement on any supported Ruby.

### Breaking

* Drop support for Ruby < 3.1. Ruby 2.3 – 3.0 are EOL upstream and are no
  longer covered by CI. Faulty now requires Ruby 3.1 or newer.
* `faulty.gemspec` declares `required_ruby_version = '>= 3.1'`, so older
  Rubies will refuse to install the gem.

### Changed

* Modernize the CI matrix: Ruby `3.1`, `3.2`, `3.3`, `3.4`, `jruby-head`,
  and `truffleruby-head`; Redis 4 and 5; OpenSearch `2.19.5` (default) and
  `3.0.0`; Elasticsearch `7.17.x` for back-compat coverage. The
  Elasticsearch 7.17 row runs the `elasticsearch:7.17.28` Docker image
  (which ships a JDK that handles cgroupv2 on current runners) against
  the `elasticsearch ~> 7.17.11` gem.
* Pass `DISABLE_INSTALL_DEMO_CONFIG=true` to the OpenSearch service
  container so OpenSearch 2.12+ doesn't require an admin-password env
  var just to boot up with the security plugin disabled.
* Replace the deprecated `:mingw` / `:x64_mingw` platform symbols in the
  `Gemfile` with the unified `:windows` symbol Bundler now expects.
* Upgrade development dependencies: `rubocop ~> 1.84`, `rubocop-rspec ~> 3.9`,
  `simplecov-cobertura ~> 3.1`, `opensearch-ruby ~> 3.4`.
* `LogListener` now lazy-requires `logger` only when constructing the
  default `Logger.new($stderr)`. Consumers that pass their own logger or
  run under Rails do not need the stdlib `logger` gem on the load path.
  This keeps Faulty boot-clean on Ruby 3.5+ where `logger` is no longer a
  default gem.

### Removed

* Drop Redis 3 from the test matrix.
* Drop the Ruby 2.3 carve-out in `spec/spec_helper.rb` that conditionally
  loaded the `mysql2` patch.

[0.11.0] - 2023-04-26
---------------------

### Added

* Add storage support for redis gem v5 #63 justinhoward
* Add Redis 5 support for patch #67 justinhoward

[0.10.0] - 2023-04-05
---------------------

### Added

* Support the opensearch-ruby gem #65 justinhoward

### Changed

* Split CI tasks into their own jobs #64 justinhoward

[0.9.0] - 2022-08-18
---------------------

### Added

* Setup codecov code coverage #57 justinhoward

### Fixed

* Fix a regression where ConnectionPool was required for the redis storage #58 justinhoward

### Changed

* Change current_time to a float #59 justinhoward

### Removed

* Remove features deprecated in 0.8.5 #60 justinhoward

### Breaking

* `Faulty.current_time` is now a float instead of an integer
* The 3 argument form of `Storage::Interface#entry` deprecated in 0.8.5 is now
  removed.
* The `error_module` circuit option deprecated in 0.8.5 is now removed.

[0.8.7] - 2022-08-11
-------------------

### Added

* Add a Faulty#clear method to reset all circuits #55 justinhoward

### Fixed

* Update rubocop cleanup gemspec #56 justinhoward

[0.8.6] - 2022-02-24
-------------------

### Added

* Define an inspect method that represent circuit #50 JuanitoFatas

[0.8.5] - 2022-02-17
-------------------

### Added

* Add granular errors for Elasticsearch patch #48 justinhoward

### Fixed

* Fix yard warnings #49 justinhoward
* Fix crash in Redis storage backend if opened_at was missing #46 justinhoward

### Changed

* Return status conditionally for Storage::Interface#entry #45 justinhoward

### Deprecations

* Storage::Interface#entry should now accept an additional parameter
  `status`. If given, the method must return the updated status,
  otherwise if status is `nil` #entry may return nil. Previously #entry
  always returned a history array.
* The error_module option is deprecated. Patches should use the error_mapper
  option instead. The option will be removed in 0.9

[0.8.4] - 2022-01-28
-------------------

### Added

* Add Elasticsearch client patch #44 justinhoward

[0.8.2] - 2021-10-18
-------------------

### Fixed

* Fix crash for older versions of concurrent-ruby #42 justinhoward

[0.8.1] - 2021-09-22
-------------------

### Changed

* Add cause message to CircuitTrippedError #40 justinhoward

### Fixed

* Record failures for cache hits #41 justinhoward

[0.8.0] - 2021-09-14
-------------------

### Added

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

[0.7.2] - 2021-09-02
-------------------

### Added

* Add Faulty.disable! for disabling globally #38 justinhoward

### Changed

* Suppress circuit_success for proxy circuits #39 justinhoward

[0.7.1] - 2021-09-02
-------------------

### Fixed

* Fix success event crash in log listener #37 justinhoward

[0.7.0] - 2021-09-02
-------------------

### Added

* Add initial benchmarks and performance improvements #36 justinhoward

### Breaking Changes

The `circuit_success` event no longer contains the status value. Computing this
value was causing performance problems.

[0.6.0] - 2021-06-10
-------------------

### Added

* Capture an error for BUSY redis backend when patched #30 justinhoward
* Add a patch for mysql2 #28 justinhoward

### Fixed

* docs, use correct state in description for skipped event #27 senny
* Fix CI to set REDIS_VERSION correctly #31 justinhoward
* Fix a potential memory leak in patches #32 justinhoward

[0.5.1] - 2021-05-28
-------------------

### Fixed

* Fix Storage::FaultTolerantProxy to return empty history on entries fail #26 justinhoward

[0.5.0] - 2021-05-28
-------------------

### Added

* Allow creating a new Faulty instance in Faulty#register #24 justinhoward
* Add support for patches to core dependencies starting with redis #14 justinhoward

### Fixed

* Improve storage #entries performance by returning entries #23 justinhoward

### Breaking Changes

* Faulty #[] no longer differentiates between symbols and strings when accessing
  Faulty instances
* Faulty::Storage::Interface must now return a history array instead of a
  circuit status object. Custom storage backends must be updated.

[0.4.0] - 2021-02-19
-------------------

### Added

* Explicitly add support for Redis 3 and 4 #15 justinhoward
* Allow setting default circuit options on Faulty instances #16 justinhoward

### Changed

* Switch from Travis CI to GitHub actions #11 justinhoward
* Only run rubocop for Ruby 2.7 in CI #12 justinhoward
* Switch to codacy for quality metrics #17 justinhoward
* Allow passing custom circuit to AutoWire #22 justinhoward

### Fixed

* Small logic fix to README #19 silasb
* Fix Redis storage dependency on ConnectionPool #21 justinhoward

### Breaking Changes

AutoWire.new is replaced with AutoWire.wrap and no longer creates an instance
of AutoWire.

[0.3.0] - 2020-10-24
-------------------

### Added

* Add tools for backend fault-tolerance #10
  * CircuitProxy for wrapping storage in an internal circuit
  * FallbackChain storage backend for falling back to stable storage
  * Timeout warnings for Redis backend
  * AutoWire wrappers for automatically configuring storage and cache
  * Better documentation for fault-tolerance

[0.2.0] - 2020-10-18
-------------------

### Changed

* Remove Scopes and replace them with Faulty instances #9

### Breaking Changes

* `Faulty::Scope` has been removed. Use `Faulty.new` instead.
* `Faulty` is now a class, not a module

[0.1.5] - 2020-10-18
-------------------

### Fixed

* Fix redis storage to expire state key when using CAS #8

[0.1.4] - 2020-10-18
-------------------

### Fixed

* Improve spec coverage for supporting classes #6
* Fix redis bug where concurrent CAS requests could crash #7

[0.1.3] - 2020-09-29
-------------------

### Added

* Add HoneybadgerListener for error reporting #4

### Fixed

* Fix bug where memory storage would delete the newest entries #5

[0.1.2] - 2020-08-28
-------------------

### Fixed

* Fix Storage::FaultTolerantProxy open and reopen methods #2

[0.1.1] - 2020-08-28
-------------------

### Fixed

* Fix a crash when Storage::FaultTolerantProxy created a status stub #1

[0.1.0] - 2020-08-27
-------------------

Initial public release

[Unreleased]: https://github.com/ParentSquare/faulty/compare/v0.13.0...HEAD
[0.13.0]: https://github.com/ParentSquare/faulty/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/ParentSquare/faulty/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/ParentSquare/faulty/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/ParentSquare/faulty/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/ParentSquare/faulty/compare/v0.8.7...v0.9.0
[0.8.7]: https://github.com/ParentSquare/faulty/compare/v0.8.6...v0.8.7
[0.8.6]: https://github.com/ParentSquare/faulty/compare/v0.8.5...v0.8.6
[0.8.5]: https://github.com/ParentSquare/faulty/compare/v0.8.4...v0.8.5
[0.8.4]: https://github.com/ParentSquare/faulty/compare/v0.8.2...v0.8.4
[0.8.2]: https://github.com/ParentSquare/faulty/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/ParentSquare/faulty/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/ParentSquare/faulty/compare/v0.7.2...v0.8.0
[0.7.2]: https://github.com/ParentSquare/faulty/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/ParentSquare/faulty/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/ParentSquare/faulty/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/ParentSquare/faulty/compare/v0.5.1...v0.5.0
[0.5.1]: https://github.com/ParentSquare/faulty/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/ParentSquare/faulty/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/ParentSquare/faulty/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/ParentSquare/faulty/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ParentSquare/faulty/compare/v0.1.5...v0.2.0
[0.1.5]: https://github.com/ParentSquare/faulty/releases/tag/v0.1.4...v0.1.5
[0.1.4]: https://github.com/ParentSquare/faulty/releases/tag/v0.1.3...v0.1.4
[0.1.3]: https://github.com/ParentSquare/faulty/releases/tag/v0.1.2...v0.1.3
[0.1.2]: https://github.com/ParentSquare/faulty/releases/tag/v0.1.1...v0.1.2
[0.1.1]: https://github.com/ParentSquare/faulty/releases/tag/v0.1.0...v0.1.1
[0.1.0]: https://github.com/ParentSquare/faulty/releases/tag/v0.1.0
