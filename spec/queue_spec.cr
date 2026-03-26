require "./spec_helper"

describe "Named Queues" do
  describe "queue declaration" do
    it "defaults to the configured routing_key when no queue is declared" do
      MyWorkerHelper::MyWorker.queue_name.should eq(TJLavin.configuration.routing_key)
    end

    it "defaults to the configured routing_key for explicitly undeclared workers" do
      CustomQueueWorkerHelper::DefaultQueueWorker.queue_name.should eq(TJLavin.configuration.routing_key)
    end

    it "uses the declared queue name" do
      CustomQueueWorkerHelper::MediaWorker.queue_name.should eq("media_processing")
    end
  end

  describe "queue registry" do
    it "registers the default queue" do
      TJLavin::Base.queues.should contain(TJLavin.configuration.routing_key)
    end

    it "registers custom queue names" do
      TJLavin::Base.queues.should contain("media_processing")
    end
  end

  describe "enqueue and consume on default queue" do
    it "enqueues and consumes a job on the default queue" do
      name = "Default Queue Test"

      MyWorkerHelper::MyWorker.new(name: name).enqueue

      consume_jobs do |job_run|
        job_run.type.should eq("MyWorkerHelper::MyWorker")
        job_run.config.should eq({"name" => name})
        job_run.job.as(MyWorkerHelper::MyWorker).name.should eq(name)
      end
    end

    it "enqueues and consumes a job with priority on the default queue" do
      name = "Priority Test"

      MyWorkerHelper::MyWorker.new(name: name).enqueue(priority: 10)

      consume_jobs do |job_run|
        job_run.type.should eq("MyWorkerHelper::MyWorker")
        job_run.config.should eq({"name" => name})
      end
    end
  end

  describe "enqueue and consume on named queue" do
    it "enqueues and consumes a job on a custom queue" do
      media_id = "media-123"

      CustomQueueWorkerHelper::MediaWorker.new(media_id: media_id).enqueue

      consume_jobs(queue: "media_processing") do |job_run|
        job_run.type.should eq("CustomQueueWorkerHelper::MediaWorker")
        job_run.config.should eq({"media_id" => media_id})
        job_run.job.as(CustomQueueWorkerHelper::MediaWorker).media_id.should eq(media_id)
      end
    end

    it "enqueues and consumes a job with priority on a custom queue" do
      media_id = "media-456"

      CustomQueueWorkerHelper::MediaWorker.new(media_id: media_id).enqueue(priority: 100)

      consume_jobs(queue: "media_processing") do |job_run|
        job_run.type.should eq("CustomQueueWorkerHelper::MediaWorker")
        job_run.config.should eq({"media_id" => media_id})
      end
    end

    it "does not deliver custom queue jobs to the default queue" do
      media_id = "media-isolated"

      CustomQueueWorkerHelper::MediaWorker.new(media_id: media_id).enqueue

      expect_raises(Exception, /Timeout/) do
        consume_jobs(timeout: 2.seconds) do |_job_run|
          raise "Should not receive media job on default queue"
        end
      end

      # Clean up: consume from the correct queue
      consume_jobs(queue: "media_processing") do |job_run|
        job_run.config["media_id"].should eq(media_id)
      end
    end

    it "does not deliver default queue jobs to a custom queue" do
      name = "Default Only"

      MyWorkerHelper::MyWorker.new(name: name).enqueue

      expect_raises(Exception, /Timeout/) do
        consume_jobs(queue: "media_processing", timeout: 2.seconds) do |_job_run|
          raise "Should not receive default job on media_processing queue"
        end
      end

      # Clean up: consume from the correct queue
      consume_jobs do |job_run|
        job_run.config["name"].should eq(name)
      end
    end
  end
end
