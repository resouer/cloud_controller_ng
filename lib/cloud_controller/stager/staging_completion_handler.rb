module VCAP::CloudController
  class StagingCompletionHandler
    attr_reader :message_bus

    def initialize(message_bus, diego_client)
      @message_bus = message_bus
      @diego_client = diego_client
    end

    StagingResponseSchema = Membrane::SchemaParser.parse do
      {
        "app_id" => String,
        "task_id" => String,
        "buildpack_key" => String,
        "detected_buildpack" => String,
        optional("detected_start_command") => String,
      }
    end

    def subscribe!
      @message_bus.subscribe("diego.staging.finished", queue: "cc") do |payload|
        logger.info("diego.staging.finished", :response => payload)

        if payload["error"]
          handle_failure(logger, payload)
        else
          handle_success(logger, payload)
        end
      end
    end

    def logger
      @logger ||= Steno.logger("cc.stager")
    end

    private

    def handle_failure(logger, payload)
      app = get_app(logger, payload)
      return if app.nil?

      app.mark_as_failed_to_stage
      Loggregator.emit_error(app.guid, "Failed to stage application: #{payload["error"]}")
    end

    def handle_success(logger, payload)
      begin
        StagingResponseSchema.validate(payload)
      rescue Membrane::SchemaValidationError => e
        logger.error("diego.staging.invalid-message", payload: payload, error: e.to_s)
        return
      end

      app = get_app(logger, payload)
      return if app.nil?

      app.update_detected_buildpack(payload["detected_buildpack"], payload["buildpack_key"])
      app.current_droplet.update_start_command(payload["detected_start_command"])

      if @diego_client.running_enabled(app)
        @diego_client.send_desire_request(app)
      else
        DeaClient.start(app, instances_to_start: app.instances)
      end
    end

    def get_app(logger, payload)
      app = App.find(guid: payload["app_id"])

      if app == nil
        logger.info(
            "diego.staging.unknown-app",
            :response => payload,
        )

        return
      end

      if payload["task_id"] != app.staging_task_id
        logger.info(
            "diego.staging.not-current",
            :response => payload,
            :current => app.staging_task_id,
        )

        return
      end

      app
    end
  end
end

