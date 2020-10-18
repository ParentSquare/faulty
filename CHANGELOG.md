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
