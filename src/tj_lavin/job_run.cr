module TJLavin
  class JobRun
    getter type
    getter job : QueuedJob?
    property config

    def initialize(type : String)
      new type
    end

    def initialize(@type : String)
      @job = nil
      @config = {} of String => String
    end

    def build_job : QueuedJob
      if job = @job
        return job
      end

      @job = instance = Base.job_for_type(type).new

      if instance.responds_to? :vars_from
        instance.vars_from(config)
      end

      instance
    end

    def run
      instance = build_job
      instance.run
      instance
    end
  end
end
