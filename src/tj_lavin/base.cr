module TJLavin
  class Base
    class_getter mapping = {} of String => Job.class

    def self.register_job_mapping(string, klass)
      @@mapping[string] = klass
    end

    def self.job_for_type(type : String) : Job.class
      @@mapping[type]
    rescue e : KeyError
      error = <<-TEXT
      Could not find a job class for type "#{type}", perhaps you forgot to register it?

      Current known types are:

      TEXT

      error += @@mapping.keys.map { |k| "- #{k}" }.join "\n"
      error += "\n\n"

      raise KeyError.new(error)
    end
  end
end
