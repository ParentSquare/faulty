# Faulty

[![Gem Version](https://badge.fury.io/rb/faulty.svg)](https://badge.fury.io/rb/faulty)
[![CI](https://github.com/ParentSquare/faulty/workflows/CI/badge.svg)](https://github.com/ParentSquare/faulty/actions?query=workflow%3ACI+branch%3Amaster)
[![Code Quality](https://app.codacy.com/project/badge/Grade/16bb1df1569a4ddba893a866673dac2a)](https://www.codacy.com/gh/ParentSquare/faulty/dashboard?utm_source=github.com&amp;utm_medium=referral&amp;utm_content=ParentSquare/faulty&amp;utm_campaign=Badge_Grade)
[![Code Coverage](https://codecov.io/gh/ParentSquare/faulty/branch/master/graph/badge.svg?token=1NDT4FW1YJ)](https://codecov.io/gh/ParentSquare/faulty)
[![Inline docs](http://inch-ci.org/github/ParentSquare/faulty.svg?branch=master)](http://inch-ci.org/github/ParentSquare/faulty)

Fault-tolerance tools for ruby based on [circuit-breakers][martin fowler].

**Without Faulty**

External dependencies like APIs can start failing at any time When they do, it
could cause cascading failures in your application.

```ruby
# The application will always try to execute this even if the API
# fails repeatedly
api.users
```

**With Faulty**

Faulty monitors errors inside this block and will "trip" a circuit if your
threshold is passed. Once a circuit is tripped, Faulty stops executing this
block until it recovers. Your application can detect external failures, and
prevent their effects from degrading overall performance.

```ruby
users = Faulty.circuit('api').try_run do

  # If this raises an exception, it counts towards the failure rate
  # The exceptions that count as failures are configurable
  # All failures will be sent to your event listeners for monitoring
  api.users

end.or_default([])
# Here we return a stubbed value so the app can continue to function
# Another strategy is just to re-raise the exception so the app can handle it
# or use its default error handler
```

See [What is this for?](#what-is-this-for) for a more detailed explanation.
Also see "Release It!: Design and Deploy Production-Ready Software" by
[Michael T. Nygard][michael nygard] and the
[Martin Fowler Article][martin fowler] post on circuit breakers.

## Contents

* [Installation](#installation)
* [API Docs](#api-docs)
* [Setup](#setup)
* [Basic Usage](#basic-usage)
* [What is this for?](#what-is-this-for-)
* [Configuration](#configuration)
  + [Configuring the Storage Backend](#configuring-the-storage-backend)
    - [Memory](#memory)
    - [Redis](#redis)
    - [FallbackChain](#fallbackchain)
    - [Storage::FaultTolerantProxy](#storagefaulttolerantproxy)
    - [Storage::CircuitProxy](#storagecircuitproxy)
  + [Configuring the Cache Backend](#configuring-the-cache-backend)
    - [Null](#null)
    - [Rails](#rails)
    - [Cache::FaultTolerantProxy](#cachefaulttolerantproxy)
    - [Cache::CircuitProxy](#cachecircuitproxy)
  + [Multiple Configurations](#multiple-configurations)
    - [The default instance](#the-default-instance)
    - [Multiple Instances](#multiple-instances)
    - [Standalone Instances](#standalone-instances)
* [Working with circuits](#working-with-circuits)
  + [Running a Circuit](#running-a-circuit)
    - [With Exceptions](#with-exceptions)
    - [With Faulty::Result](#with-faultyresult)
  + [Specifying the Captured Errors](#specifying-the-captured-errors)
  + [Using the Cache](#using-the-cache)
  + [Configuring the Circuit Threshold](#configuring-the-circuit-threshold)
    - [Rate Threshold](#rate-threshold)
    - [Sample Threshold](#sample-threshold)
    - [Cool Down](#cool-down)
  + [Circuit Options](#circuit-options)
  + [Listing Circuits](#listing-circuits)
  + [Locking Circuits](#locking-circuits)
* [Patches](#patches)
  + [Patch::Redis](#patchredis)
  + [Patch::Mysql2](#patchmysql2)
  + [Patch::Elasticsearch](#patchelasticsearch)
* [Event Handling](#event-handling)
  + [CallbackListener](#callbacklistener)
  + [Other Built-in Listeners](#other-built-in-listeners)
  + [Custom Listeners](#custom-listeners)
* [Disabling Faulty Globally](#disabling-faulty-globally)
* [Testing with Faulty](#testing-with-faulty)
* [How it Works](#how-it-works)
  + [Caching](#caching)
  + [Fault Tolerance](#fault-tolerance)
* [Implementing a Cache Backend](#implementing-a-cache-backend)
* [Implementing a Storage Backend](#implementing-a-storage-backend)
* [Alternatives](#alternatives)
  + [Currently Active](#currently-active)
  + [Previous Work](#previous-work)
  + [Faulty's Unique Features](#faulty-s-unique-features)

## Installation

Add it to your `Gemfile`:

```ruby
gem 'faulty'
```

Or install it manually:

```sh
gem install faulty
```

During your app startup, call
[`Faulty.init`](https://www.rubydoc.info/gems/faulty/Faulty.init).
For Rails, you would do this in `config/initializers/faulty.rb`. See
[Setup](#setup) for details.

## API Docs

API docs can be read [on rubydoc.info][api docs], inline in the source code, or
you can generate them yourself with Ruby `yard`:

```sh
bin/yardoc
```

Then open `doc/index.html` in your browser.

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

Or use a faulty instance instead for an object-oriented approach

```ruby
faulty = Faulty.new do
  config.storage = Faulty::Storage::Redis.new
end
```

For a full list of configuration options, see the
[Configuration](#configuration) section.

## Basic Usage

To create a circuit, call
[`Faulty.circuit`](https://www.rubydoc.info/gems/faulty/Faulty.circuit).
This can be done as you use the circuit, or you can set it up beforehand. Any
options passed to the `circuit` method are synchronized across threads and saved
as long as the process is alive.

```ruby
circuit1 = Faulty.circuit(:api, rate_threshold: 0.6)

# The options from above are also used when called here
circuit2 = Faulty.circuit(:api)
circuit2.options.rate_threshold == 0.6 # => true

# The same circuit is returned on each consecutive call
circuit1.equal?(circuit2) # => true
```

To run a circuit, call the `run` method:

```ruby
Faulty.circuit(:api).run do
  api.users
end
```

See [How it Works](#how-it-works) for more details about how Faulty handles
circuit failures.

If the `run` block above fails, a
[`Faulty::CircuitError`](https://www.rubydoc.info/gems/faulty/Faulty/CircuitError)
will be raised. It is up to your application to handle that error however
necessary or crash. Often though, you don't want to crash your application when
a circuit fails, but instead apply a fallback or default behavior. For this,
Faulty provides the `try_run` method:

```ruby
result = Faulty.circuit(:api).try_run do
  api.users
end

users = if result.ok?
  result.get
else
  []
end
```

The [`try_run`](https://www.rubydoc.info/gems/faulty/Faulty/Circuit:try_run)
method returns a result type instead of raising errors. See the API docs for
[`Result`](https://www.rubydoc.info/gems/faulty/Faulty/Result) for more
information. Here we use it to check whether the result is `ok?` (not an error).
If it is we set the users variable, otherwise we set a default of an empty
array. This pattern is so common, that `Result` also implements a helper method
`or_default` to do the same thing:

```ruby
users = Faulty.circuit(:api).try_run do
  api.users
end.or_default([])
```

If you want to globally wrap your core dependencies, like your cache or
database, you may want to look at [Patches](#patches), which can automatically
wrap your connections in a Faulty circuit.

See [Running a Circuit](#running-a-circuit) for more in-depth examples. Also,
make sure you have proper [Event Handlers](#event-handling) setup so that you
can monitor your circuits for failures.

## What is this for?

Circuit breakers are a fault-tolerance tool for creating separation between your
application and external dependencies. For example, your application may call an
external API to send a text message:

```ruby
TextApi.send(message)
```

In normal operation, this API call is very fast. However what if the texting
service started hanging? Your application would quickly use up a lot of
resources waiting for requests to return from the service. You could consider
adding a timeout to your request:

```ruby
TextApi.send(message, timeout: 5)
```

Now your application will terminate requests after 5 seconds, but that could
still add up to a lot of resources if you call this thousands of times. Circuit
breakers solve this problem.

```ruby
Faulty.circuit('text_api').run do
  TextApi.send(message, timeout: 5)
end
```

Now, when the text API hangs, the first few will run and start timing out. This
will trip the circuit. After the circuit trips
(see [How it Works](#how-it-works)), calls to the text API will be paused for
the configured cool down period. Your application resources are not overwhelmed.

You are free to implement a fallback or error handling however you wish, for
example, in this case, you might add the text message to a failure queue:

```ruby
Faulty.circuit('text_api').run do
  TextApi.send(message, timeout: 5)
rescue Faulty::CircuitError => e
  FailureQueue.enqueue(message)
end
```

## Configuration

Faulty can be configured with the following configuration options. This example
illustrates the default values. In the first example, we configure Faulty
globally. The second example shows the same configuration using an instance of
Faulty instead of global configuration.

```ruby
Faulty.init do |config|
  # The cache backend to use. By default, Faulty looks for a Rails cache. If
  # that's not available, it uses an ActiveSupport::Cache::Memory instance.
  # Otherwise, it uses a Faulty::Cache::Null and caching is disabled.
  # Whatever backend is given here is automatically wrapped in
  # Faulty::Cache::AutoWire. This adds fault-tolerance features, see the
  # AutoWire API docs for more details.
  config.cache = Faulty::Cache::Default.new

  # A hash of default options to be used when creating new Circuits.
  # See Circuit Options below for a full list of these
  config.circuit_defaults = {}

  # The storage backend. By default, Faulty uses an in-memory store. For most
  # production applications, you'll want a more robust backend. Faulty also
  # provides Faulty::Storage::Redis for this.
  # Whatever backend is given here is automatically wrapped in
  # Faulty::Storage::AutoWire. This adds fault-tolerance features, see the
  # AutoWire APi docs for more details. If an array of storage backends is
  # given, each one will be tried in order until one succeeds.
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

Here is the same configuration using an instance of `Faulty`. This is a more
object-oriented approach.

```ruby
faulty = Faulty.new do |config|
  config.cache = Faulty::Cache::Default.new
  config.storage = Faulty::Storage::Memory.new
  config.listeners = [Faulty::Events::LogListener.new]
  config.notifier = Faulty::Events::Notifier.new(config.listeners)
end
```

Most of the examples in this README use the global Faulty class methods, but
they work the same way when using an instance. Just substitute your instance
instead of `Faulty`. There is no preferred way to use Faulty. Choose whichever
configuration mechanism works best for your application. Also see
[Multiple Configurations](#multiple-configurations) if your application needs
to set different options in different scenarios.

For all Faulty APIs that have configuration, you can also pass in an options
hash. For example, `Faulty.init` could be called like this:

```ruby
Faulty.init(cache: Faulty::Cache::Null.new)
```

### Configuring the Storage Backend

A storage backend is required to use Faulty. By default, it uses in-memory
storage, but Redis is also available, along with a number of wrappers used to
improve resiliency and fault-tolerance.

#### Memory

The
[`Faulty::Storage::Memory`](https://www.rubydoc.info/gems/faulty/Faulty/Storage/Memory)
backend is the default storage backend. You may prefer this implementation if
you want to avoid the complexity and potential failure-mode of cross-network
circuit storage. The trade-off is that circuit state is only contained within a
single process and will not be saved across application restarts. Locks will
also be cleared on restart.

The default configuration:

```ruby
Faulty.init do |config|
  config.storage = Faulty::Storage::Memory.new do |storage|
    # The maximum number of circuit runs that will be stored
    storage.max_sample_size = 100
  end
end
```

#### Redis

The [`Faulty::Storage::Redis`](https://www.rubydoc.info/gems/faulty/Faulty/Storage/Redis)
backend provides distributed circuit storage using Redis. Although Faulty takes
steps to reduce risk (See [Fault Tolerance](#fault-tolerance)), using
cross-network storage does introduce some additional failure modes. To reduce
this risk, be sure to set conservative timeouts for your Redis connection.
Setting high timeouts will print warnings to stderr.

The default configuration:

```ruby
Faulty.init do |config|
  config.storage = Faulty::Storage::Redis.new do |storage|
    # The Redis client. Accepts either a Redis instance, or a ConnectionPool
    # of Redis instances. A low timeout is highly recommended to prevent
    # cascading failures when evaluating circuits.
    storage.client = ::Redis.new(timeout: 1)

    # The prefix to prepend to all redis keys used by Faulty circuits
    storage.key_prefix = 'faulty'

    # A string to separate the parts of the redis key
    storage.key_separator = ':'

    # The maximum number of circuit runs that will be stored
    storage.max_sample_size = 100

    # The maximum number of seconds that a circuit run will be stored
    storage.sample_ttl = 1800

    # The maximum number of seconds to store a circuit. Does not apply to
    # locks, which are indefinite.
    storage.circuit_ttl = 604_800 # 1 Week

    # The number of seconds between circuit expirations. Changing this setting
    # is not recommended. See API docs for more implementation details.
    storage.list_granularity = 3600

    # If true, disables warnings about recommended client settings like timeouts
    storage.disable_warnings = false
  end
end
```

#### FallbackChain

The [`Faulty::Storage::FallbackChain`](https://www.rubydoc.info/gems/faulty/Faulty/Storage/FallbackChain)
backend is a wrapper for multiple prioritized storage backends. If the first
backend in the chain fails, consecutive backends are tried until one succeeds.
The recommended use-case for this is to fall back on reliable storage if a
networked storage backend fails.

For example, you may configure Redis as your primary storage backend, with an
in-memory storage backend as a fallback:

```ruby
Faulty.init do |config|
  config.storage = Faulty::Storage::FallbackChain.new([
    Faulty::Storage::Redis.new,
    Faulty::Storage::Memory.new
  ])
end
```

Faulty instances will automatically use a fallback chain if an array is given to
the `storage` option, so this example is equivalent to the above:

```ruby
Faulty.init do |config|
  config.storage = [
    Faulty::Storage::Redis.new,
    Faulty::Storage::Memory.new
  ]
end
```

If the fallback chain fails-over to backup storage, circuit states will not
carry over, so failover could be temporarily disruptive to your application.
However, any calls to `#lock` or `#unlock` will always be persisted to all
backends so that locks are maintained during failover.

#### Storage::FaultTolerantProxy

This wrapper is applied to all non-fault-tolerant storage backends by default
(see the [API docs for `Faulty::Storage::AutoWire`](https://www.rubydoc.info/gems/faulty/Faulty/Storage/AutoWire)).

[`Faulty::Storage::FaultTolerantProxy`](https://www.rubydoc.info/gems/faulty/Faulty/Storage/FaultTolerantProxy)
is a wrapper that suppresses storage errors and returns sensible defaults during
failures. If a storage backend is failing, all circuits will be treated as
closed regardless of locks or previous history.

If you wish your application to use a secondary storage backend instead of
failing closed, use [`FallbackChain`](#storagefallbackchain).

#### Storage::CircuitProxy

This wrapper is applied to all non-fault-tolerant storage backends by default
(see the [API docs for `Faulty::Storage::AutoWire`](https://www.rubydoc.info/gems/faulty/Faulty/Cache/AutoWire)).

[`Faulty::Storage::CircuitProxy`](https://www.rubydoc.info/gems/faulty/Faulty/Storage/CircuitProxy)
is a wrapper that uses an independent in-memory circuit to track failures to
storage backends. If a storage backend fails continuously, it will be
temporarily disabled and raise `Faulty::CircuitError`s.

Typically this is used inside a [`FaultTolerantProxy`](#storagefaulttolerantproxy) or
[`FallbackChain`](#storagefallbackchain) so that these storage failures are handled
gracefully.

### Configuring the Cache Backend

#### Null

The [`Faulty::Cache::Null`](https://www.rubydoc.info/gems/faulty/Faulty/Cache/Null)
cache disables caching. It is the default if Rails and ActiveSupport are not
present.

#### Rails

[`Faulty::Cache::Rails`](https://www.rubydoc.info/gems/faulty/Faulty/Cache/Rails)
is the default cache if Rails or ActiveSupport are present. If Rails is present,
it uses `Rails.cache` as the backend. If ActiveSupport is present, but Rails is
not, it creates a new `ActiveSupport::Cache::MemoryStore` by default.  This
backend can be used with any `ActiveSupport::Cache`.

```ruby
Faulty.init do |config|
  config.cache = Faulty::Cache::Rails.new(
    ActiveSupport::Cache::RedisCacheStore.new
  )
end
```

#### Cache::FaultTolerantProxy

This wrapper is applied to all non-fault-tolerant cache backends by default
(see the API docs for `Faulty::Cache::AutoWire`).

[`Faulty::Cache::FaultTolerantProxy`](https://www.rubydoc.info/gems/faulty/Faulty/Cache/FaultTolerantProxy)
is a wrapper that suppresses cache errors and acts like a null cache during
failures. Reads always return `nil`, and writes are no-ops.

#### Cache::CircuitProxy

This wrapper is applied to all non-fault-tolerant circuit backends by default
(see the API docs for `Faulty::Circuit::AutoWire`).

[`Faulty::Cache::CircuitProxy`](https://www.rubydoc.info/gems/faulty/Faulty/Cache/CircuitProxy)
is a wrapper that uses an independent in-memory circuit to track failures to
cache backends. If a cache backend fails continuously, it will be
temporarily disabled and raise `Faulty::CircuitError`s.

Typically this is used inside a
[`FaultTolerantProxy`](#cachefaulttolerantproxy) so that these cache failures
are handled gracefully.

### Multiple Configurations

It is possible to have multiple configurations of Faulty running within the same
process. The most common setup is to simply use `Faulty.init` to
configure Faulty globally, however it is possible to have additional
configurations.

#### The default instance

When you call [`Faulty.init`](https://www.rubydoc.info/gems/faulty/Faulty.init),
you are actually creating the default instance of `Faulty`. You can access this
instance directly by calling
[`Faulty.default`](https://www.rubydoc.info/gems/faulty/Faulty.default).

```ruby
# We create the default instance
Faulty.init

# Access the default instance
faulty = Faulty.default

# Alternatively, access the instance by name
faulty = Faulty[:default]
```

You can rename the default instance if desired:

```ruby
Faulty.init(:custom_default)

instance = Faulty.default
instance = Faulty[:custom_default]
```

#### Multiple Instances

If you want multiple instance, but want global, thread-safe access to
them, you can use
[`Faulty.register`](https://www.rubydoc.info/gems/faulty/Faulty.register):

```ruby
api_faulty = Faulty.new do |config|
  # This accepts the same options as Faulty.init
end

Faulty.register(:api, api_faulty)

# Now access the instance globally
Faulty[:api]
```

When you call [`Faulty.circuit`](https://www.rubydoc.info/gems/faulty/Faulty.circuit),
that's the same as calling `Faulty.default.circuit`, so you can apply the same
principal to any other registered Faulty instance:

```ruby
Faulty[:api].circuit('api_circuit').run { 'ok' }
```

You can also create and register a Faulty instance in one step:

```ruby
Faulty.register(:api) do |config|
  # This accepts the same options as Faulty.init
end
```

#### Standalone Instances

If you choose, you can use Faulty instances without registering them globally by
simply calling [`Faulty.new`](https://www.rubydoc.info/gems/faulty/Faulty:initialize).
This is more object-oriented and is necessary if you use dependency injection.

```ruby
faulty = Faulty.new
faulty.circuit('standalone_circuit')
```

Calling `#circuit` on the instance still has the same memoization behavior that
`Faulty.circuit` has, so subsequent runs for the same circuit will use a
memoized circuit object.


## Working with circuits

A circuit can be created by calling the `#circuit` method on `Faulty`, or on
your Faulty instance:

```ruby
# With global Faulty configuration
circuit = Faulty.circuit('api')

# Or with a Faulty instance
circuit = faulty.circuit('api')
```

### Running a Circuit

You can handle circuit errors either with exceptions, or with a Faulty
[`Result`](https://www.rubydoc.info/gems/faulty/Faulty/Result). They both have
the same behavior, but you can choose whatever syntax is more convenient for
your use-case.

#### With Exceptions

If we want exceptions to be raised, we use the
[`#run`](https://www.rubydoc.info/gems/faulty/Faulty/Circuit:run) method. This
does not suppress exceptions, only monitors them. If `api.users` raises an
exception here, it will bubble up to the caller. The exception will be a
sub-class of [`Faulty::CircuitError`](https://www.rubydoc.info/gems/faulty/Faulty/CircuitError),
and the error `cause` will be the original error object.

```ruby
begin
  Faulty.circuit('api').run do
    api.users
  end
rescue Faulty::CircuitError => e
  e.cause # The original error
end
```

#### With Faulty::Result

Sometimes exception handling is awkward to deal with, and could cause a lot of
extra boilerplate code. In simple cases, it's can be more concise to allow
Faulty to capture exceptions. Use the
[`#try_run`](https://www.rubydoc.info/gems/faulty/Faulty/Circuit:try_run) method
for this.

```ruby
  result = Faulty.circuit('api').try_run do
    api.users
  end
```

The `result` variable is an instance of
[`Faulty::Result`](https://www.rubydoc.info/gems/faulty/Faulty/Result). A result
can either be an error if the circuit failed, or an "ok" value if it succeeded.

You can check whether it's an error with the `ok?` or `error?` method.

```ruby
if result.ok?
  users = result.get
else
  error = result.error
end
```

Sometimes you want your application to crash when a circuit fails, but other
times, you might want to return a default or fallback value. The `Result` object
has a method [`#or_default`](https://www.rubydoc.info/gems/faulty/Faulty/Result:or_default)
to do that.

```ruby
# Users will be nil if the result is an error
users = result.or_default

# Users will be an empty array if the result is an error
users = result.or_default([])

# Users will be the return value of the block
users = result.or_default do
  # ...
end
```

As we showed in the [Basic Usage](#basic-usage) section, you can put this
together in a nice one-liner.

```ruby
Faulty.circuit('api').try_run { api.users }.or_default([])
```

### Specifying the Captured Errors

By default, Faulty circuits will capture all `StandardError` errors, but
sometimes you might not want every error to count as a circuit failure. For
example, an HTTP 404 Not Found response typically should not cause a circuit to
fail. You can customize the errors that Faulty captures

```ruby
Faulty.circuit('api', errors: [Net::HTTPServerException]).run do
  # If this raises any exception other than Net::HTTPServerException
  # Faulty will not capture it at all, and it will not count as a circuit failure
  api.find_user(3)
end
```

Or, if you'd instead like to specify errors to be excluded:

```ruby
Faulty.circuit('api', exclude: [Net::HTTPClientException]).run do
  # If this raises a Net::HTTPClientException, Faulty will not capture it
  api.find_user(3)
end
```

Both options can even be specified together.

```ruby
Faulty.circuit(
  'api',
  errors: [ActiveRecord::ActiveRecordError],
  exclude: [ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique]
).run do
  # This only captures ActiveRecord::ActiveRecordError errors, but not
  # ActiveRecord::RecordNotFound or ActiveRecord::RecordNotUnique errors
  user = User.find(3)
  user.save!
end
```

### Using the Cache

Circuit runs can be given a cache key, and if they are, the result of the circuit
block will be cached. Calls to that circuit block will try to fetch from the
cache, and only execute the block if the cache misses.

```ruby
Faulty.circuit('api').run(cache: 'all_users') do
  api.users
end
```

The cache will be refreshed (meaning the circuit will be allowed to execute)
after `cache_refreshes_after` (default 900 second). However, the value remains
stored in the cache for `cache_expires_in` (default 86400 seconds, 1 day). If
the circuit fails, the last cached value will be returned even if
`cache_refreshes_after` has passed.

See the [Caching](#caching) section for more details on Faulty's caching
strategy.

### Configuring the Circuit Threshold

To configure how a circuit responds to error, use the `cool_down`,
`rate_threshold` and `sample_threshold` options.

#### Rate Threshold

The first option to look at is `rate_threshold`. This specifies the percentage
of circuit runs that must fail before a circuit is opened.

```ruby
# This circuit must fail 70% of the time before the circuit will be tripped
Faulty.circuit('api', rate_threshold: 0.7).run { api.users }
```

#### Sample Threshold

We typically don't want circuits to trip immediately if the first execution
fails. This is why we have the `sample_threshold` option. The circuit will never
be tripped until we record at least this number of executions.

```ruby
# This circuit must run 10 times before it is allowed to trip. Those 10 runs
# can be successes or fails. If at least 70% of them are failures, the circuit
# will be opened.
Faulty.circuit('api', sample_threshold: 10, rate_threshold: 0.7).run { api.users }
```

#### Cool Down

The `cool_down` option specifies how much time to wait after a circuit is
opened. During this period, the circuit will not be executed. After the cool
down elapses, the circuit enters the "half open" state, and execution can be
retried. See [How it Works](#how-it-works).

```ruby
# If this circuit trips, it will skip executions for 120 seconds before retrying
Faulty.circuit('api', cool_down: 120).run { api.users }
```

### Circuit Options

A circuit can be created with the following configuration options. Those options
are only set once, synchronized across threads, and will persist in-memory until
the process exits. If you're using [multiple configurations](#multiple-configurations),
the options are retained within the context of each instance. All options given
after the first call to `Faulty.circuit` (or `Faulty#circuit`) are ignored.

```ruby
Faulty.circuit('api', rate_threshold: 0.7).run { api.call }

# These options are ignored since with already initialized the circuit
circuit = Faulty.circuit('api', rate_threshold: 0.3)
circuit.options.rate_threshold # => 0.7
```

This is because the circuit objects themselves are internally memoized, and are
read-only once they are run.

The following example represents the defaults for a new circuit:

```ruby
Faulty.circuit('api') do |config|
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

  # The number of seconds of history that is considered when calculating
  # the circuit failure rate. The length of the sliding window.
  config.evaluation_window = 60

  # The errors that will be captured by Faulty and used to trigger circuit
  # state changes.
  config.errors = [StandardError]

  # Errors that should be ignored by Faulty and not captured.
  config.exclude = []

  # The event notifier. Inherits the Faulty instance notifier by default
  config.notifier = Faulty.options.notifier

  # The minimum failure rate required to trip a circuit
  config.rate_threshold = 0.5

  # The minimum number of runs required before a circuit can trip
  config.sample_threshold = 3

  # The storage backend for this circuit. Inherits the Faulty instance storage
  # by default
  config.storage = Faulty.options.storage
end
```

Following the same convention as `Faulty.init`, circuits can also be created
with an options hash:

```ruby
Faulty.circuit(:api, cache_expires_in: 1800)
```

### Listing Circuits

For monitoring or debugging, you may need to retrieve a list of all circuit
names. This is possible with [`Faulty.list_circuits`](https://www.rubydoc.info/gems/faulty/Faulty.list_circuits)
(or [`Faulty#list_circuits`](https://www.rubydoc.info/gems/faulty/Faulty:list_circuits)
if you're using an instance).

You can get a list of all circuit statuses by mapping those names to their
status objects. Be careful though, since this could cause performance issues for
very large numbers of circuits.

```ruby
statuses = Faulty.list_circuits.map do |name|
  Faulty.circuit(name).status
end
```

### Locking Circuits

It is possible to lock a circuit open or closed. A circuit that is locked open
will never execute its block, and always raise an `Faulty::OpenCircuitError`.
This is useful in cases where you need to manually disable a dependency
entirely. If a cached value is available, that will be returned from the circuit
until it expires, even outside its refresh period.

* [`lock_open!`](https://www.rubydoc.info/gems/faulty/Faulty/Circuit:lock_open!)
* [`lock_closed!`](https://www.rubydoc.info/gems/faulty/Faulty/Circuit:lock_closed!)
* [`unlock!`](https://www.rubydoc.info/gems/faulty/Faulty/Circuit:unlock!)

```ruby
Faulty.circuit('broken_api').lock_open!
```

A circuit that is locked closed will never trip. This is useful in cases where a
circuit is continuously tripping incorrectly. If a cached value is available, it
will have the same behavior as an unlocked circuit.

```ruby
Faulty.circuit('false_positive').lock_closed!
```

To remove a lock of either type:

```ruby
Faulty.circuit('fixed').unlock!
```

Locking or unlocking a circuit has no concurrency guarantees, so it's not
recommended to lock or unlock circuits from production code. Instead, locks are
intended as an emergency tool for troubleshooting and debugging.

## Patches

For certain core dependencies like a cache or a database connection, it is
inconvenient to wrap every call in its own circuit. Faulty provides some patches
to wrap these calls in a circuit automatically. To use a patch, it first needs
to be loaded. Since patches modify third-party code, they are not automatically
required with the Faulty gem, so they need to be required individually.

```ruby
require 'faulty'
require 'faulty/patch/redis'
```

Or require them in your `Gemfile`

```ruby
gem 'faulty', require: %w[faulty faulty/patch/redis]
```

For core dependencies you'll most likely want to use the in-memory circuit
storage adapter and not the Redis storage adapter. That way if Redis fails, your
circuit storage doesn't also fail, causing cascading failures.

For example, you can use a separate Faulty instance to manage your Mysql2
circuit:

```ruby
# Setup your default config. This can use the Redis backend if you prefer
Faulty.init do |config|
  # ...
end

Faulty.register(:mysql) do |config|
  # Here we decide to set some circuit defaults more useful for
  # frequent database calls
  config.circuit_defaults = {
    cool_down: 20.0,
    evaluation_window: 40,
    sample_threshold: 25
  }
end

# Now we can use our "mysql" faulty instance when constructing a Mysql2 client
Mysql2::Client.new(host: '127.0.0.1', faulty: { instance: 'mysql2' })
```

### Patch::Redis

[`Faulty::Patch::Redis`](https://www.rubydoc.info/gems/faulty/Faulty/Patch/Redis)
protects a Redis client with an internal circuit. Pass a `:faulty` key along
with your connection options to enable the circuit breaker.

The Redis patch supports the Redis gem versions 3 and 4.

```ruby
require 'faulty/patch/redis'

redis = Redis.new(url: 'redis://localhost:6379', faulty: {
  # The name for the redis circuit
  name: 'redis'

  # The faulty instance to use
  # This can also be a registered faulty instance or a constant name. See API
  # docs for more details
  instance: Faulty.default

  # By default, circuit errors will be subclasses of Redis::BaseError
  # To disable this behavior, set patch_errors to false and Faulty
  # will raise its default errors
  patch_errors: true
})
redis.connect # raises Faulty::CircuitError if connection fails

# If the faulty key is not given, no circuit is used
redis = Redis.new(url: 'redis://localhost:6379')
redis.connect # not protected by a circuit
```

### Patch::Mysql2

[`Faulty::Patch::Mysql2`](https://www.rubydoc.info/gems/faulty/Faulty/Patch/Mysql2)
protects a `Mysql2::Client` with an internal circuit. Pass a `:faulty` key along
with your connection options to enable the circuit breaker.

Faulty supports the mysql2 gem versions 0.5 and greater.

Note: Although Faulty supports Ruby 2.3 in general, the Mysql2 patch is not
fully supported on Ruby 2.3. It may work for you, but use it at your own risk.

```ruby
require 'faulty/patch/mysql2'

mysql = Mysql2::Client.new(host: '127.0.0.1', faulty: {
  # The name for the Mysql2 circuit
  name: 'mysql2'

  # The faulty instance to use
  # This can also be a registered faulty instance or a constant name. See API
  # docs for more details
  instance: Faulty.default

  # By default, circuit errors will be subclasses of
  # Mysql2::Error::ConnectionError
  # To disable this behavior, set patch_errors to false and Faulty
  # will raise its default errors
  patch_errors: true
})

mysql.query('SELECT * FROM users') # raises Faulty::CircuitError if connection fails

# If the faulty key is not given, no circuit is used
mysql = Mysql2::Client.new(host: '127.0.0.1')
mysql.query('SELECT * FROM users') # not protected by a circuit
```
### Patch::Postgres

[`Faulty::Patch::Postgres`](https://www.rubydoc.info/gems/faulty/Faulty/Patch/Postgres)
protects a `PG::Connection` with an internal circuit. Pass a `:faulty` key along
with your connection options to enable the circuit breaker.

Faulty supports the pg gem versions 1.0 and greater.

```ruby
require 'faulty/patch/postgres'

pg = PG::Connection.new(host: 'localhost', faulty: {
  # The name for the Postgres circuit
  name: 'postgres'

  # The faulty instance to use
  # This can also be a registered faulty instance or a constant name. See API
  # docs for more details
  instance: Faulty.default

  # By default, circuit errors will be subclasses of PG::Error
  # To disable this behavior, set patch_errors to false and Faulty
  # will raise its default errors
  patch_errors: true
})
```



### Patch::Elasticsearch

[`Faulty::Patch::Elasticsearch`](https://www.rubydoc.info/gems/faulty/Faulty/Patch/Elasticsearch)
protects a `Elasticsearch::Client` with an internal circuit. Pass a `:faulty` key along
with your client options to enable the circuit breaker.

```ruby
require 'faulty/patch/elasticsearch'

es = Elasticsearch::Client.new(url: 'localhost:9200', faulty: {
  # The name for the Elasticsearch::Client circuit
  name: 'elasticsearch'

  # The faulty instance to use
  # This can also be a registered faulty instance or a constant name. See API
  # docs for more details
  instance: Faulty.default

  # By default, circuit errors will be subclasses of
  # Elasticsearch::Transport::Transport::Error
  # To disable this behavior, set patch_errors to false and Faulty
  # will raise its default errors
  patch_errors: true
})
```

If you're using Searchkick, you can configure Faulty with `client_options`.

```ruby
Searchkick.client_options[:faulty] = { name: 'searchkick' }
```

## Event Handling

Faulty uses an event-dispatching model to deliver notifications of internal
events. The full list of events is available from
[`Faulty::Events::EVENTS`](https://www.rubydoc.info/gems/faulty/Faulty/Events).

- `cache_failure` -  A cache backend raised an error. Payload: `key`, `action`, `error`
- `circuit_cache_hit` -  A circuit hit the cache. Payload: `circuit`, `key`
- `circuit_cache_miss` -  A circuit hit the cache. Payload: `circuit`, `key`
- `circuit_cache_write` - A circuit wrote to the cache. Payload: `circuit`, `key`
- `circuit_closed` - A circuit closed. Payload: `circuit`
- `circuit_failure` - A circuit execution raised an error. Payload: `circuit`,
  `status`, `error`
- `circuit_opened` - A circuit execution caused the circuit to open. Payload
  `circuit`, `error`
- `circuit_reopened` - A circuit execution cause the circuit to reopen from
  half-open. Payload: `circuit`, `error`.
- `circuit_skipped` - A circuit execution was skipped because the circuit is
  open. Payload: `circuit`
- `circuit_success` - A circuit execution was successful. Payload: `circuit`
- `storage_failure` - A storage backend raised an error. Payload `circuit` (can
  be nil), `action`, `error`

By default events are logged using `Faulty::Events::LogListener`, but that can
be replaced, or additional listeners can be added.

### CallbackListener

The [`CallbackListener`](https://www.rubydoc.info/gems/faulty/Faulty/Events/CallbackListener)
is useful for ad-hoc handling of events. You can specify an event handler by
calling a method on the callback handler by the same name.

```ruby
Faulty.init do |config|
  # Replace the default listener with a custom callback listener
  listener = Faulty::Events::CallbackListener.new do |events|
    events.circuit_opened do |payload|
      MyNotifier.alert("Circuit #{payload[:circuit].name} opened: #{payload[:error].message}")
    end
  end
  config.listeners = [listener]
end
```

### Other Built-in Listeners

In addition to the log and callback listeners, Faulty intends to implement
built-in service-specific handlers to make it easy to integrate with monitoring
and reporting software.

* [`Faulty::Events::LogListener`](https://www.rubydoc.info/gems/faulty/Faulty/Events/LogListener):
  Logs all circuit events to a specified `Logger` or `$stderr` by default. This
  is enabled by default if no listeners are specified.
* [`Faulty::Events::HoneybadgerListener`](https://www.rubydoc.info/gems/faulty/Faulty/Events/HoneybadgerListener):
  Reports circuit and backend errors to the Honeybadger error reporting service.

If your favorite monitoring software is not supported here, please open a PR
that implements a listener for it.

### Custom Listeners

You can implement your own listener by following the documentation in
[`Faulty::Events::ListenerInterface`](https://www.rubydoc.info/gems/faulty/Faulty/Events/ListenerInterface).
For example:

```ruby
class MyFaultyListener
  def handle(event, payload)
    MyNotifier.alert(event, payload)
  end
end
```

```ruby
Faulty.init do |config|
  config.listeners = [MyFaultyListener.new]
end
```

## Disabling Faulty Globally

For testing or for some environments, you may wish to disable Faulty circuits
at a global level.

```ruby
Faulty.disable!
```

This only affects the process where you run the `#disable!` method and it does
not affect the stored state of circuits.

Faulty will **still use the cache** even when disabled. If you also want to
disable the cache, configure Faulty to use a `Faulty::Cache::Null` cache.

## Testing with Faulty

Depending on your application, you could choose to
[disable Faulty globally](#disabling-faulty-globally), but sometimes you may
want to test your application's behavior in a failure scenario.

If you have such tests, you will want to prevent failures in one test from
affecting other tests. To clear all circuit states between tests, use `#clear!`.
For example, with rspec:

```ruby
RSpec.configure do |config|
  config.after do
    Faulty.clear!
  end
end
```

## How it Works

Faulty implements a version of circuit breakers inspired by "Release It!: Design
and Deploy Production-Ready Software" by [Michael T. Nygard][michael nygard] and
[Martin Fowler's post][martin fowler] on the subject. A few notable features of
Faulty's implementation are:

- Rate-based failure thresholds
- Integrated caching inspired by Netflix's [Hystrix][hystrix] with automatic
  cache jitter and error fallback.
- Event-based monitoring
- Flexible fault-tolerant storage with optional fallbacks

Following the principals of the circuit-breaker pattern, the block given to
`run` or `try_run` will always be executed as long as it never raises an error.
If the block _does_ raise an error, then the circuit keeps track of the number
of runs and the failure rate.

Once both thresholds are breached, the circuit is opened. Once open, the
circuit starts the cool-down period. Any executions within that cool-down are
skipped, and a `Faulty::OpenCircuitError` will be raised.

After the cool-down has elapsed, the circuit enters the half-open state. In this
state, Faulty allows a single execution of the block as a test run. If the test
run succeeds, the circuit is fully closed and the circuit state is reset. If the
test run fails, the circuit is opened and the cool-down is reset.

Each time the circuit changes state or executes the block, events are raised
that are sent to the Faulty event notifier. The notifier should be used to track
circuit failure rates, open circuits, etc.

In addition to the classic circuit breaker design, Faulty implements caching
that is integrated with the circuit state. See [Caching](#caching) for more
detail.

### Caching

Faulty integrates caching into it's circuits in a way that is particularly
suited to fault-tolerance. To make use of caching, you must specify the `cache`
configuration option when initializing Faulty or creating a new Faulty instance.
If you're using Rails, this is automatically set to the Rails cache.

Once your cache is configured, you can use the `cache` parameter when running
a circuit to specify a cache key:

```ruby
feed = Faulty.circuit('rss_feeds')
  .try_run(cache: "rss_feeds/#{feed}") do
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
code above, if the circuit is closed, the block will be executed. If the block
succeeds, the cache is refreshed. If the block fails, the default of `[]` will
be returned.

### Fault Tolerance

Faulty backends are fault-tolerant by default. Any `StandardError`s raised by
the storage or cache backends are captured and suppressed. Failure events for
these errors are sent to the notifier.

In case of a flaky storage or cache backend, Faulty also uses independent
in-memory circuits to track failures so that we don't keep calling a backend
that is failing. See the API docs for [`Cache::AutoWire`](https://www.rubydoc.info/gems/faulty/Faulty/Cache/AutoWire),
and [`Storage::AutoWire`](https://www.rubydoc.info/gems/faulty/Faulty/Storage/AutoWire)
for more details.

If the storage backend fails, circuits will default to closed. If the cache
backend fails, all cache queries will miss.

## Implementing a Cache Backend

You can implement your own cache backend by following the documentation in
[`Faulty::Cache::Interface`](https://www.rubydoc.info/gems/faulty/Faulty/Cache/Interface).
It is a fairly simple API, with only get/set methods. For example:

```ruby
class MyFaultyCache
  def initialize(my_cache)
    @cache = my_cache
  end

  def read(key)
    @cache.read(key)
  end

  def write(key, value, expires_in: nil)
    @cache.write(key, value, expires_in)
  end

  # Set this to false unless your cache never raises errors
  def fault_tolerant?
    false
  end
end
```

Feel free to open a pull request if your cache backend would be useful for other
users.

## Implementing a Storage Backend

You can implement your own storage backend by following the documentation in
[`Faulty::Storage::Interface`](https://www.rubydoc.info/gems/faulty/Faulty/Storage/Interface).
Since the storage has some tricky requirements regarding concurrency, the
[`Faulty::Storage::Memory`](https://www.rubydoc.info/gems/faulty/Faulty/Storage/Memory)
can be used as a reference implementation. Feel free to open a pull request if
your storage backend would be useful for other users.

## Alternatives

Faulty has its own opinions about how to implement a circuit breaker in Ruby,
but there are and have been many other options:

### Currently Active

- [semian](https://github.com/Shopify/semian): A resiliency toolkit that
  includes circuit breakers. It auto-wires circuits for MySQL, Net::HTTP, and
  Redis. It has only in-memory storage by design. Its core components are
  written in C, which allows it to be faster than pure ruby.
- [circuitbox](https://github.com/yammer/circuitbox): Also uses a block syntax
  to manually define circuits. It uses Moneta to abstract circuit storage to
  allow any key-value store.

### Previous Work

- [circuit_breaker-ruby](https://github.com/scripbox/circuit_breaker-ruby) (no
  recent activity)
- [stoplight](https://github.com/orgsync/stoplight) (unmaintained)
- [circuit_breaker](https://github.com/wsargent/circuit_breaker) (no recent
activity)
- [simple_circuit_breaker](https://github.com/soundcloud/simple_circuit_breaker)
  (unmaintained)
- [breaker](https://github.com/ahawkins/breaker) (unmaintained)
- [circuit_b](https://github.com/alg/circuit_b) (unmaintained)

### Faulty's Unique Features

- Simple API but configurable for advanced users
- Pluggable storage backends (circuitbox also has this)
- Patches for common core dependencies (semian also has this)
- Protected storage access with fallback to safe storage
- Global, or object-oriented configuration with multiple instances
- Integrated caching support tailored for fault-tolerance
- Manually lock circuits open or closed

[api docs]: https://www.rubydoc.info/github/ParentSquare/faulty/master
[michael nygard]: https://www.michaelnygard.com/
[martin fowler]: https://www.martinfowler.com/bliki/CircuitBreaker.html
[hystrix]: https://github.com/Netflix/Hystrix/wiki/How-it-Works
