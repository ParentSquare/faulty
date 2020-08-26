# Faulty

Fault-tolerance tools for ruby based on [circuit-breakers][martin fowler].

```ruby
users = Faulty.circuit(:api).try_run do
  api.users
end.or_default([])
```

## Installation

Add it to your `Gemfile`:

```ruby
gem 'faulty'
```

Or install it manually:

```sh
gem 'faulty'
```

During your app startup, call `Faulty.init`. For Rails, you would do this in
`config/initializers/faulty.rb`.

## Setup

Use the default configuration options:

```ruby
Faulty.init
```

Or specify your own configuration:

```ruby
Faulty.init do |config|
  config.storage = Faulty::Storage::Redis.new

  config.listeners << Faulty::Events::CallbackListener.new do |events|
    events.circuit_open do |payload|
      puts 'Circuit was opened'
    end
  end
end
```

For a full list of configuration options, see the
[Configuration](#configuration) section.

## Basic Usage

## Global Configuration

`Faulty.init` can set the following global configuration options. This example
illustrates the default values. It is also possible to define multiple
non-global configuration scopes (see [Scopes](#scopes)).

```ruby
Faulty.init do |config|
  # The cache backend to use. By default, Faulty looks for a Rails cache. If
  # that's not available, it uses an ActiveSupport::Cache::Memory instance.
  # Otherwise, it uses a Faulty::Cache::Null and caching is disabled.
  config.cache = Faulty::Cache::Default.new

  # The storage backend. By default, Faulty uses an in-memory store. For most
  # production applications, you'll want a more robust backend. Faulty also
  # provides Faulty::Storage::Redis for this.
  config.storage = Faulty::Storage::Memory.new

  # An array of event listeners. Each object in the array should implement
  # Faulty::Events::ListenerInterface. For ad-hoc custom listeners, Faulty
  # provides Faulty::Events::CallbackListener.
  config.listeners = [Faulty::Events::LogListener.new]

  # The event notifier. For most use-cases, you don't need to change this,
  # However, Faulty allows substituting your own notifier if necessary.
  # If overridden, config.listeners will be ignored.
  config.notifier = Faulty::Events::Notifier.new(config.listeners)
end
```

For all Faulty APIs that have configuration, you can also pass in an options
hash. For example, `Faulty.init` could be called like this:

```ruby
Faulty.init(cache: Faulty::Cache::Null.new)
```

## Faulty's Circuit Breaker Algorithm

Faulty implements a version of circuit breakers inspired by
[Martin Fowler's post][martin fowler] on the subject. A few notable features of
Faulty's implementation are:

- Rate-based failure thresholds
- Integrated caching inspired by Netflix's [Hystrix][hystrix] with automatic
  cache jitter and error fallback.
- Event-based monitoring

TODO: Full algorithm

## Circuit Options

A circuit can be created with the following configuration options. Those options
are only set once, and will persist in-memory until the process exits. If
you're using [scopes](#scopes), the options are retained within the context of
each scope. All options given after the first call to `Faulty.circuit` (or
`Scope.circuit` are ignored.

This is because the circuit objects themselves are internally memoized, and are
read-only once created.

The following example represents the defaults for a new circuit:

```ruby
Faulty.circuit(:api) do |config|
  # The cache backend for this circuit. Inherits the global cache by default.
  config.cache = Faulty.options.cache

  # The number of seconds before a cache entry is expired. After this time, the
  # cache entry may be fully deleted. If set to nil, the cache will not expire.
  config.cache_expires_in = 86400

  # The number of seconds before a cache entry should be refreshed. See the
  # Caching section for more detail. A value of nil disables cache refreshing.
  config.cache_refreshes_after = 900

  # The number of seconds to add or subtract from cache_refreshes_after
  # when determining whether a cache entry should be refreshed. Helps mitigate
  # the "thundering herd" effect
  config.cache_refresh_jitter = 0.2 * config.cache_refreshes_after

  # After a circuit is opened, the number of seconds to wait before moving the
  # circuit to half-open.
  config.cool_down = 300

  # The errors that will be captured by Faulty and used to trigger circuit
  # state changes.
  config.errors = [StandardError]

  # Errors that should be ignored by Faulty and not captured.
  config.exclude = []

  # The event notifier. Inherits the global notifier by default
  config.notifier = Faulty.options.notifier

  # The minimum failure rate required to trip a circuit
  config.rate_threshold = 0.5

  # The minimum number of runs required before a circuit can trip
  config.sample_threshold = 3

  # The storage backend for this circuit. Inherits the global storage by default
  config.storage = Faulty.options.storage
end
```

Following the same convention as `Faulty.init`, circuits can also be created
with an options hash:

```ruby
Faulty.circuit(:api, cache_expires_in: 1800)
```

## Caching

Faulty integrates caching into it's circuits in a way that is particularly
suited to fault-tolerance. To make use of caching, you must specify the `cache`
configuration option when initializing Faulty or creating a scope. If you're
using Rails, this is automatically set to the Rails cache.

Once your cache is configured, you can use the `cache` parameter when running
a circuit:

```ruby
feed = Faulty.circuit(:rss_feeds)
  .try_run(cache: "rss_feeds/#{feed}" do
    fetch_feed(feed)
  end.or_default([])
```

By default a circuit has the following options:

- `cache_expires_in`: 86400 (1 day). This is sent to the cache backend and
  defines how long the cache entry should be stored. After this time elapses,
  queries will result in a cache miss.
- `cache_refreshes_after`: 900 (15 minutes). This is used internally by Faulty
  to indicate when a cache should be refreshed. It does not affect how long the
  cache entry is stored.
- `cache_refresh_jitter`: 180 (3 minutes = 20% of `cache_refreshes_after`). The
  maximum number of seconds to randomly add or subtract from
  `cache_refreshes_after` when determining whether to refresh a cache entry.
  This mitigates the "thundering herd" effect caused by many processes
  simultaneously refreshing the cache.

This code will attempt to fetch an RSS feed protected by a circuit. If the feed
is within the cache refresh period, then the result will be returned from the
cache and the block will not be executed regardless of the circuit state.

If the cache is hit, but outside its refresh period, then Faulty will check the
circuit state. If the circuit is closed or half-open, then it will run the
block. If the block is successful, then it will update the circuit, write to the
cache and return the new value.

However, if the cache is hit and the block fails, then that failure is noted
in the circuit and Faulty returns the cached value.

If the circuit is open and the cache is hit, then Faulty will always return the
cached value.

If the cache query results in a miss, then faulty operates as normal. In the
code above, the block will be executed. If the block succeeds, the cache is
refreshed. If the block fails, the default of `[]` will be returned.

## Fault Tolerance

TODO

## Event Handling

TODO

## Scopes

TODO

## Implementing a Storage Backend

TODO

## Implementing a Cache Backend

TODO

## Implementing a Event Listener

TODO

## Alternatives

Faulty has its own opinions about how to implement a circuit breaker in Ruby,
but there are and have been many other options:

- [circuitbox](https://github.com/yammer/circuitbox)
- [circuit_breaker-ruby](https://github.com/scripbox/circuit_breaker-ruby)
- [stoplight](https://github.com/orgsync/stoplight) (currently unmaintained)
- [circuit_breaker](https://github.com/wooga/circuit_breaker) (archived)
- [simple_circuit_breaker](https://github.com/soundcloud/simple_circuit_breaker)
  (unmaintained)
- [breaker](https://github.com/ahawkins/breaker) (unmaintained)
- [circuit_b](https://github.com/alg/circuit_b) (unmaintained)

[martin fowler]: https://www.martinfowler.com/bliki/CircuitBreaker.html
[hystrix]: https://github.com/Netflix/Hystrix/wiki/How-it-Works
