require "base64"
require "http/client"
require "json"
require "uri"

# Minimal client for the LavinMQ/RabbitMQ management HTTP API. Used by
# specs to forcibly close AMQP connections — the spec equivalent of
# CloudAMQP cycling a node out from under the worker.
module ManagementClient
  extend self

  @@client : HTTP::Client?

  def list_connections : Array(JSON::Any)
    response = client.get("/api/connections", headers: auth_headers)
    raise "list_connections failed: #{response.status_code} #{response.body}" unless response.success?
    JSON.parse(response.body).as_a
  end

  def close_all_connections : Int32
    closed = 0
    list_connections.each do |conn|
      name = conn["name"].as_s
      response = client.delete("/api/connections/#{URI.encode_path_segment(name)}", headers: auth_headers)
      closed += 1 if response.success?
    end
    closed
  end

  private def client : HTTP::Client
    @@client ||= HTTP::Client.new(api_host, api_port)
  end

  private def auth_headers : HTTP::Headers
    headers = HTTP::Headers.new
    headers["Authorization"] = "Basic #{Base64.strict_encode("#{api_user}:#{api_password}")}"
    headers["Content-Type"] = "application/json"
    headers
  end

  private def api_host : String
    ENV["LAVINMQ_API_HOST"]? || amqp_uri.try(&.hostname.to_s) || "localhost"
  end

  private def api_port : Int32
    (ENV["LAVINMQ_API_PORT"]? || "15672").to_i
  end

  private def api_user : String
    ENV["LAVINMQ_API_USER"]? || amqp_uri.try(&.user.to_s) || "guest"
  end

  private def api_password : String
    ENV["LAVINMQ_API_PASSWORD"]? || amqp_uri.try(&.password.to_s) || "guest"
  end

  private def amqp_uri : URI?
    raw = ENV["AMQP_URL"]?
    return nil if raw.nil? || raw.empty?
    URI.parse(raw)
  end
end
