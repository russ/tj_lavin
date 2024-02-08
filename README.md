# Lavin MQ

An example worker setup file in Lucky/Avram application.

Configuration:

```
TJLavin.configure do |settings|
  settings.amqp_url = ENV["AMQP_URL"]
  settings.cluster_name = ENV["WORKER_CLUSTER_NAME"]?
  settings.topic_name = ENV["AMQP_TOPIC_NAME"].to_s
end
```

Worker setup:

```
require "./app"

Habitat.raise_if_missing_settings!

if LuckyEnv.development?
  Avram::Migrator::Runner.new.ensure_migrated!
  Avram::SchemaEnforcer.ensure_correct_column_mappings!
end

# Disable query cache because all jobs run in the
# same fiber which means infinite cache
Avram.settings.query_cache_enabled = false

# Start the server
TJLavin::Runner.start("worker_cluster_#{ARGV[0]}")
```

Worker file:

```
class BMXWorker < TJLavin::QueuedJob
  param encoding_task_id : UUID

  def perform
    puts "Keep on peddalin'"
  end
end
```
