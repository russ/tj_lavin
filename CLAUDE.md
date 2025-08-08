# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TJ Lavin is a Crystal wrapper around LavinMQ for job management, providing an AMQP-based queued job system. It enables creating background workers that process jobs through message queues with support for priorities and delayed execution.

## Build and Development Commands

### Building
```crystal
crystal build src/tj_lavin.cr
```

### Running Tests
No test framework is currently configured in this project.

### Dependencies
Install dependencies with:
```bash
shards install
```

## Architecture

### Core Components

- **Job System**: Abstract job classes with automatic serialization/deserialization
  - `Job` (src/tj_lavin/job.cr): Base abstract class for all jobs
  - `QueuedJob` (src/tj_lavin/queued_job.cr): Base class for AMQP-queued jobs with parameter handling
  - Uses Crystal macros for automatic parameter serialization and job registration

- **Job Execution**:
  - `JobRun` (src/tj_lavin/job_run.cr): Handles job instantiation and execution
  - `Runner` (src/tj_lavin/runner.cr): AMQP consumer that processes jobs from queues
  - Jobs are automatically registered in a global mapping system via macros

- **Configuration** (src/tj_lavin/configuration.cr):
  - `amqp_url`: AMQP connection string (required)
  - `topic_name`: AMQP topic name (default: "topicname")

- **Serialization** (src/tj_lavin/serializers/primatives.cr): 
  - Handles primitive type serialization for job parameters
  - Supports basic types: String, Bool, Char, UUID, integers, floats

### Job Creation Pattern

Jobs inherit from `QueuedJob` and use the `param` macro to define typed parameters:

```crystal
class MyWorker < TJLavin::QueuedJob
  param name : String
  param priority : Int32 = 5

  def perform
    # Job logic here
  end
end
```

### Queue Features

- **Priority Support**: Jobs can be enqueued with priority levels (0-255)
- **Delayed Execution**: Jobs support delay in milliseconds using x-delayed-message exchange
- **Error Handling**: Failed jobs are rejected and not requeued
- **Prefetch Control**: Workers process one job at a time (prefetch: 1)

### Configuration Example

```crystal
TJLavin.configure do |settings|
  settings.amqp_url = ENV["AMQP_URL"]
  settings.topic_name = ENV["AMQP_TOPIC_NAME"].to_s
end
```

### Worker Startup

Start workers with:
```crystal
TJLavin::Runner.start("routing_key")
```

## Key Integration Points

- Integrates with Lucky/Avram applications
- Uses LavinMQ/RabbitMQ-compatible AMQP messaging
- Supports Crystal's macro system for code generation
- Uses structured logging through Crystal's Log module