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

  listener = Faulty::Events::CallbackListener.new
  config.listeners = [
    Faulty::Events::CallbackListener.new do |events|
      events.circuit_open do |payload|
        puts 'Circuit was opened'
      end
    end
  ]
end
```

For a full list of configuration options, see the Configuration section.

## Basic Usage

## Configuration

## Faulty's Circuit Breaker Algorithm

Faulty implements a version of circuit breakers inspired by
[Martin Fowler's post][martin fowler] on the subject. A few notable features of
Faulty's implementation are:

- Rate-based failure thresholds
- Integrated caching inspired by Netflix's [Hystrix][hystrix] with automatic
  cache jitter and error fallback.
- Event-based monitoring

## Circuit Options

## Caching

Faulty integrates caching into it's circuits in a way that is particularly
suited to fault-tolerance. To make use of caching, you must specify the `cache`
configuration option when initializing Faulty. If you're using Rails, this is
automatically set to the Rails cache.

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

## Event Handling

## Scopes

## Implementing a Storage Backend

## Implementing a Cache Backend

## Implementing a Event Listener

[martin fowler]: https://www.martinfowler.com/bliki/CircuitBreaker.html
[hystrix]: https://github.com/Netflix/Hystrix/wiki/How-it-Works
