[![CI](https://github.com/russ/tj_lavin/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/russ/tj_lavin/actions/workflows/ci.yml)
[![GitHub release](https://img.shields.io/github/v/release/russ/tj_lavin)](https://github.com/russs/tj_lavin/releases)
[![GitHub](https://img.shields.io/github/license/russ/tj_lavin)](https://github.com/russ/tj_lavin/blob/master/LICENSE)

# TJ Lavin 🚴

> *"Keep on peddalin'!"* - A Crystal job queue library for background processing

TJ Lavin is a lightweight Crystal wrapper around [LavinMQ](https://lavinmq.com) that makes background job processing simple and fun. Named after the legendary BMX rider and Challenge host, it's designed to keep your application pedaling smoothly even under pressure.

## ✨ Features

- 🔥 **Simple Setup** - Get up and running in minutes
- ⚡ **Priority Queues** - Handle urgent jobs first  
- ⏰ **Delayed Jobs** - Schedule jobs for future execution
- 🛡️ **Error Handling** - Robust failure management
- 🎯 **Type Safety** - Crystal's type system keeps your jobs safe
- 🔧 **Lucky Integration** - Works seamlessly with Lucky/Avram applications

## 🚀 Quick Start

### Installation

Add this to your `shard.yml`:

```yaml
dependencies:
  tj_lavin:
    github: russ/tj_lavin
```

Then run:
```bash
shards install
```

### Configuration

Configure TJ Lavin in your application:

```crystal
TJLavin.configure do |settings|
  settings.amqp_url = ENV["AMQP_URL"]
  settings.routing_key = ENV["AMQP_ROUTING_KEY"]? # defaults to "tjlavin"
  settings.default_exchange = ENV["AMQP_DEFAULT_EXCHANGE"]? # defaults to ""
  settings.delayed_exchange = ENV["AMQP_DELAYED_EXCHANGE"]? # defaults to "tjlavin.delayed"
end
```

### Creating a Job

Define your background jobs by inheriting from `QueuedJob`:

```crystal
class BMXWorker < TJLavin::QueuedJob
  param name : String
  param skill_level : Int32 = 5

  def perform
    puts "Keep on peddalin' #{name}! Your skill level is #{skill_level}/10 🚴‍♂️"
    # Your job logic here
  end
end
```

### Enqueuing Jobs

Queue up some work:

```crystal
# Simple job
BMXWorker.new(name: "BMX Bandit").enqueue

# High priority job (0-255, higher = more priority, default is 0)
BMXWorker.new(name: "Speed Demon").enqueue(priority: 10)

# Delayed job
BMXWorker.new(name: "Future Rider").enqueue(delay: 30.seconds)
```

### Running Workers

For Lucky/Avram applications, set up your worker process:

```crystal
# worker.cr
require "./app"

Habitat.raise_if_missing_settings!

if LuckyEnv.development?
  Avram::Migrator::Runner.new.ensure_migrated!
  Avram::SchemaEnforcer.ensure_correct_column_mappings!
end

# Disable query cache for better performance in workers
Avram.settings.query_cache_enabled = false

# Start processing jobs
TJLavin::Runner.start
```

Then run your worker:
```bash
crystal worker.cr
```

## Testing with specs

To test your workers, include a spec helper like this:

```crystal
module TJLavin
  abstract class QueuedJob < Job
    ENQUEUED_JOBS = [] of String

    def enqueue(priority : Int32 = 0, delay : Time::Span = 0.seconds) : JobRun
      ENQUEUED_JOBS << self.class.name
      TJLavin::JobRun.new("nothing")
    end
  end
end

Spec.before_each do
  TJLavin::QueuedJob::ENQUEUED_JOBS.clear
end
```

Then check to make sure your job was enqueued:

```crystal
TJLavin::QueuedJob::ENQUEUED_JOBS.should contain("MyWorker")
```

## 📚 Documentation

- **Job Parameters**: Use the `param` macro to define typed parameters for your jobs
- **Error Handling**: Failed jobs are automatically rejected and logged
- **Monitoring**: Built-in logging shows job processing status
- **Serialization**: Automatic parameter serialization/deserialization

## 🤝 Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## 📄 License

Apache License 2.0 - see LICENSE file for details.

---

*Keep on peddalin'!* 🚴‍♂️
