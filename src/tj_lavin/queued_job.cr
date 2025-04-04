module TJLavin
  abstract class QueuedJob < Job
    macro inherited
      def self.job_name
        "{{ @type.id }}"
      end

      TJLavin::Base.register_job_mapping("{{ @type.id }}", {{ @type.id }})

      PARAMETERS = [] of Nil

      macro param(parameter)
        {% verbatim do %}
          {%
            unless parameter.is_a?(TypeDeclaration)
              raise "TJLavin Job: Unable to generate parameter for #{parameter}"
            end
          %}
          {%
            name = parameter.var
            value = parameter.value
            type = parameter.type
            simplified_type = nil

            unless type
              raise "TJLavin Job: Parameter types must be specified explicitly"
            end

            if type.is_a? Union
              raise "TJLavin Job: Unable to build serialization logic for Union Types: #{type}"
            else
              simplified_type = type.resolve
            end

            method_suffix = simplified_type.stringify.underscore.gsub(/::/, "__").id

            PARAMETERS << {
              name:          name,
              value:         value,
              type:          type,
              method_suffix: method_suffix,
            }
          %}

          @{{ name }} : {{ type }}?

          def {{ name }}=(value : {{simplified_type}}) : {{simplified_type}}
            @{{ name }} = value
          end

          def {{ name }}? : {{ simplified_type }} | Nil
            @{{ name }}
          end

          def {{ name }} : {{ simplified_type }}
            if ! (%object = {{ name }}?).nil?
                %object
            else
              msg = <<-MSG
                Expected a parameter named `{{ name }}` but found nil.
                The parameter may not have been provided when the job was enqueued.
                Should you be using `{{ name }}` instead?
              MSG
              raise msg
            end
          end
        {% end %}
      end

      macro finished
        {% verbatim do %}
          def initialize; end

          def initialize({{
                           PARAMETERS.map do |parameter|
                             assignment = "@#{parameter["name"]}"
                             assignment = assignment + " : #{parameter["type"]}" if parameter["type"]
                             assignment = assignment + " = #{parameter["value"]}" unless parameter["value"].is_a? Nop
                             assignment
                           end.join(", ").id
                         }})
          end

          # Methods declared in here have the side effect over overwriting any overrides which may have been implemented
          # otherwise in the job class. In order to allow folks to override the behavior here, these methods are only
          # injected if none already exists.

          {% unless @type.methods.map(&.name).includes?(:vars_from.id) %}
            def vars_from(config : Hash(String, String))
              {% for parameter in PARAMETERS %}
                @{{ parameter["name"] }} = deserialize_{{ parameter["method_suffix"] }}(config["{{ parameter["name"] }}"])
              {% end %}
            end
          {% end %}

          {% unless @type.methods.map(&.name).includes?(:build_job_run.id) %}
            def build_job_run
              job_run = TJLavin::JobRun.new(self.class.job_name)

              {% for parameter in PARAMETERS %}
                job_run.config["{{ parameter["name"] }}"] = serialize_{{ parameter["method_suffix"] }}(@{{ parameter["name"] }}.not_nil!)
              {% end %}

              job_run
            end
          {% end %}
        {% end %}
      end
    end

    def enqueue(routing_key : String, priority : Int32 = 0) : JobRun
      build_job_run.tap do |job_run|
        hash_to_array = ->(hash : Hash(String, String)) : Array(String) {
          array = [] of String

          hash.each do |key, value|
            array << key
            array << value
          end

          array
        }

        AMQP::Client.start(TJLavin.configuration.amqp_url.to_s) do |c|
          c.channel do |ch|
            q = ch.queue(routing_key, args: AMQP::Client::Arguments.new({"x-max-priority": 255}))
            q.publish(
              {
                class: job_run.type,
                args:  hash_to_array.call(job_run.config),
              }.to_json,
              props: AMQ::Protocol::Properties.new(priority: priority.to_u8),
            )
          end
        end
      end
    end
  end
end
