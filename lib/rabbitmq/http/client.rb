require "hashie"
require "faraday"
require "faraday_middleware"
require "multi_json"
require "uri"

module RabbitMQ
  module HTTP
    class Client

      #
      # API
      #

      attr_reader :endpoint

      def self.connect(endpoint, options = {})
        new(endpoint, options)
      end

      def initialize(endpoint, options = {})
        @endpoint = endpoint
        @options  = options

        initialize_connection(endpoint, options)
      end

      def overview
        decode_resource(@connection.get("overview"))
      end

      # Returns a list of messaging protocols supported by
      # the node (or cluster).
      #
      # Common values are:
      #
      # * amqp
      # * amqp/ssl
      # * mqtt
      # * stomp
      #
      # The exact value depends on RabbitMQ configuration and enabled
      # plugins.
      #
      # @return [Array<String>] Enabled protocols
      def enabled_protocols
        self.overview.listeners.
          map { |lnr| lnr.protocol }.
          uniq
      end

      # Returns a hash of protocol => port.
      #
      # @return [Hash<String, Integer>] Hash of protocol => port
      def protocol_ports
        (self.overview.listeners || []).
          reduce(Hash.new) { |acc, lnr| acc[lnr.protocol] = lnr.port; acc }
      end

      def list_nodes
        decode_resource_collection(@connection.get("nodes"))
      end

      def node_info(name)
        decode_resource(@connection.get("nodes/#{uri_encode(name)}"))
      end

      def list_extensions
        decode_resource_collection(@connection.get("extensions"))
      end

      def list_definitions
        decode_resource(@connection.get("definitions"))
      end

      def upload_definitions(defs)
        response = @connection.post("definitions") do |req|
          req.headers['Content-Type'] = "application/json"
          req.body = defs
        end
        response.success?
      end

      def list_connections
        decode_resource_collection(@connection.get("connections"))
      end

      def connection_info(name)
        decode_resource(@connection.get("connections/#{uri_encode(name)}"))
      end

      def close_connection(name)
        decode_resource(@connection.delete("connections/#{uri_encode(name)}"))
      end

      def list_channels
        decode_resource_collection(@connection.get("channels"))
      end

      def channel_info(name)
        decode_resource(@connection.get("channels/#{uri_encode(name)}"))
      end

      def list_exchanges(vhost = nil)
        path = if vhost.nil?
                 "exchanges"
               else
                 "exchanges/#{uri_encode(vhost)}"
               end

        decode_resource_collection(@connection.get(path))
      end

      def declare_exchange(vhost, name, attributes = {})
        opts = {
          :type => "direct",
          :auto_delete => false,
          :durable => true,
          :arguments => {}
        }.merge(attributes)

        response = @connection.put("exchanges/#{uri_encode(vhost)}/#{uri_encode(name)}") do |req|
          req.headers['Content-Type'] = 'application/json'
          req.body = MultiJson.dump(opts)
        end
        decode_resource(response)
      end

      def delete_exchange(vhost, name, if_unused = false)
        response = @connection.delete("exchanges/#{uri_encode(vhost)}/#{uri_encode(name)}") do |req|
          req.params["if-unused"] = true if if_unused
        end
        decode_resource(response)
      end

      def exchange_info(vhost, name)
        decode_resource(@connection.get("exchanges/#{uri_encode(vhost)}/#{uri_encode(name)}"))
      end

      def list_bindings_by_source(vhost, exchange)
        decode_resource_collection(@connection.get("exchanges/#{uri_encode(vhost)}/#{uri_encode(exchange)}/bindings/source"))
      end

      def list_bindings_by_destination(vhost, exchange)
        decode_resource_collection(@connection.get("exchanges/#{uri_encode(vhost)}/#{uri_encode(exchange)}/bindings/destination"))
      end

      def list_queues(vhost = nil)
        path = if vhost.nil?
                 "queues"
               else
                 "queues/#{uri_encode(vhost)}"
               end

        decode_resource_collection(@connection.get(path))
      end

      def queue_info(vhost, name)
        decode_resource(@connection.get("queues/#{uri_encode(vhost)}/#{uri_encode(name)}"))
      end

      def declare_queue(vhost, name, attributes)
        response = @connection.put("queues/#{uri_encode(vhost)}/#{uri_encode(name)}") do |req|
          req.headers['Content-Type'] = "application/json"
          req.body = MultiJson.dump(attributes)
        end
        decode_resource(response)
      end

      def delete_queue(vhost, name)
        decode_resource(@connection.delete("queues/#{uri_encode(vhost)}/#{uri_encode(name)}"))
      end

      def list_queue_bindings(vhost, queue)
        decode_resource_collection(@connection.get("queues/#{uri_encode(vhost)}/#{uri_encode(queue)}/bindings"))
      end

      def purge_queue(vhost, name)
        @connection.delete("queues/#{uri_encode(vhost)}/#{uri_encode(name)}/contents")
        Hashie::Mash.new
      end

      def get_messages(vhost, name, options)
        response = @connection.post("queues/#{uri_encode(vhost)}/#{uri_encode(name)}/get") do |req|
          req.headers['Content-Type'] = "application/json"
          req.body = MultiJson.dump(options)
        end
        decode_resource_collection(response)
      end

      def list_bindings(vhost = nil)
        path = if vhost.nil?
                 "bindings"
               else
                 "bindings/#{uri_encode(vhost)}"
               end

        decode_resource_collection(@connection.get(path))
      end

      def list_bindings_between_queue_and_exchange(vhost, queue, exchange)
        decode_resource_collection(@connection.get("bindings/#{uri_encode(vhost)}/e/#{uri_encode(exchange)}/q/#{uri_encode(queue)}"))
      end

      def queue_binding_info(vhost, queue, exchange, properties_key)
        decode_resource(@connection.get("bindings/#{uri_encode(vhost)}/e/#{uri_encode(exchange)}/q/#{uri_encode(queue)}/#{uri_encode(properties_key)}"))
      end

      def bind_queue(vhost, queue, exchange, routing_key, arguments = [])
        resp = @connection.post("bindings/#{uri_encode(vhost)}/e/#{uri_encode(exchange)}/q/#{uri_encode(queue)}") do |req|
          req.headers['Content-Type'] = 'application/json'
          req.body = MultiJson.dump({:routing_key => routing_key, :arguments => arguments})
        end
        resp.headers['location']
      end

      def delete_queue_binding(vhost, queue, exchange, properties_key)
        resp = @connection.delete("bindings/#{uri_encode(vhost)}/e/#{uri_encode(exchange)}/q/#{uri_encode(queue)}/#{uri_encode(properties_key)}")
        resp.success?
      end

      def list_bindings_between_exchanges(vhost, destination_exchange, source_exchange)
        decode_resource_collection(@connection.get("bindings/#{uri_encode(vhost)}/e/#{uri_encode(source_exchange)}/e/#{uri_encode(destination_exchange)}"))
      end

      def exchange_binding_info(vhost, destination_exchange, source_exchange, properties_key)
        decode_resource(@connection.get("bindings/#{uri_encode(vhost)}/e/#{uri_encode(source_exchange)}/e/#{uri_encode(destination_exchange)}/#{uri_encode(properties_key)}"))
      end


      def bind_exchange(vhost, destination_exchange, source_exchange, routing_key, arguments = [])
        resp = @connection.post("bindings/#{uri_encode(vhost)}/e/#{uri_encode(source_exchange)}/e/#{uri_encode(destination_exchange)}") do |req|
          req.headers['Content-Type'] = 'application/json'
          req.body = MultiJson.dump({:routing_key => routing_key, :arguments => arguments})
        end
        resp.headers['location']
      end

      def delete_exchange_binding(vhost, destination_exchange, source_exchange, properties_key)
        resp = @connection.delete("bindings/#{uri_encode(vhost)}/e/#{uri_encode(source_exchange)}/e/#{uri_encode(destination_exchange)}/#{uri_encode(properties_key)}")
        resp.success?
      end


      def list_vhosts
        decode_resource_collection(@connection.get("vhosts"))
      end

      def vhost_info(name)
        decode_resource(@connection.get("vhosts/#{uri_encode(name)}"))
      end

      def create_vhost(name)
        response = @connection.put("vhosts/#{uri_encode(name)}") do |req|
          req.headers['Content-Type'] = "application/json"
        end
        decode_resource(response)
      end

      def delete_vhost(name)
        decode_resource(@connection.delete("vhosts/#{uri_encode(name)}"))
      end



      def list_permissions(vhost = nil)
        path = if vhost
                 "vhosts/#{uri_encode(vhost)}/permissions"
               else
                 "permissions"
               end

        decode_resource_collection(@connection.get(path))
      end

      def list_permissions_of(vhost, user)
        decode_resource(@connection.get("permissions/#{uri_encode(vhost)}/#{uri_encode(user)}"))
      end

      def update_permissions_of(vhost, user, attributes)
        response = @connection.put("permissions/#{uri_encode(vhost)}/#{uri_encode(user)}") do |req|
          req.headers['Content-Type'] = "application/json"
          req.body = MultiJson.dump(attributes)
        end
        decode_resource(response)
      end

      def clear_permissions_of(vhost, user)
        decode_resource(@connection.delete("permissions/#{uri_encode(vhost)}/#{uri_encode(user)}"))
      end



      def list_users
        decode_resource_collection(@connection.get("users"))
      end

      def user_info(name)
        decode_resource(@connection.get("users/#{uri_encode(name)}"))
      end

      def update_user(name, attributes)
        attributes[:tags] ||= ""

        response = @connection.put("users/#{uri_encode(name)}") do |req|
          req.headers['Content-Type'] = "application/json"
          req.body = MultiJson.dump(attributes)
        end
        decode_resource(response)
      end
      alias create_user update_user

      def delete_user(name)
        decode_resource(@connection.delete("users/#{uri_encode(name)}"))
      end

      def user_permissions(name)
        decode_resource_collection(@connection.get("users/#{uri_encode(name)}/permissions"))
      end

      def whoami
        decode_resource(@connection.get("whoami"))
      end



      def list_policies(vhost = nil)
        path = if vhost
                 "policies/#{uri_encode(vhost)}"
               else
                 "policies"
               end

        decode_resource_collection(@connection.get(path))
      end

      def list_policies_of(vhost, name = nil)
        path = if name
                 "policies/#{uri_encode(vhost)}/#{uri_encode(name)}"
               else
                 "policies/#{uri_encode(vhost)}"
               end
        decode_resource_collection(@connection.get(path))
      end

      def update_policies_of(vhost, name, attributes)
        response = @connection.put("policies/#{uri_encode(vhost)}/#{uri_encode(name)}") do |req|
          req.headers['Content-Type'] = "application/json"
          req.body = MultiJson.dump(attributes)
        end
        decode_resource(response)
      end

      def clear_policies_of(vhost, name)
        decode_resource(@connection.delete("policies/#{uri_encode(vhost)}/#{uri_encode(name)}"))
      end




      def list_parameters(component = nil)
        path = if component
                 "parameters/#{uri_encode(component)}"
               else
                 "parameters"
               end
        decode_resource_collection(@connection.get(path))
      end

      def list_parameters_of(component, vhost, name = nil)
        path = if name
                 "parameters/#{uri_encode(component)}/#{uri_encode(vhost)}/#{uri_encode(name)}"
               else
                 "parameters/#{uri_encode(component)}/#{uri_encode(vhost)}"
               end
        decode_resource_collection(@connection.get(path))
      end

      def update_parameters_of(component, vhost, name, attributes)
        response = @connection.put("parameters/#{uri_encode(component)}/#{uri_encode(vhost)}/#{uri_encode(name)}") do |req|
          req.headers['Content-Type'] = "application/json"
          req.body = MultiJson.dump(attributes)
        end
        decode_resource(response)
      end

      def clear_parameters_of(component, vhost, name)
        decode_resource(@connection.delete("parameters/#{uri_encode(component)}/#{uri_encode(vhost)}/#{uri_encode(name)}"))
      end



      def aliveness_test(vhost)
        r = @connection.get("aliveness-test/#{uri_encode(vhost)}")
        r.body["status"] == "ok"
      end


      protected

      def initialize_connection(endpoint, options = {})
        uri     = URI.parse(endpoint)
        uri.path = "/api" if ["","/"].include?(uri.path)
        user     = uri.user     || options.delete(:username) || "guest"
        password = uri.password || options.delete(:password) || "guest"
        options = options.merge(:url => uri.to_s)
        adapter = options.delete(:adapter) || Faraday.default_adapter

        @connection = Faraday.new(options) do |conn|
          conn.basic_auth user, password
          conn.use        FaradayMiddleware::FollowRedirects, :limit => 3
          conn.use        Faraday::Response::RaiseError
          conn.response   :json, :content_type => /\bjson$/

          conn.adapter    adapter
        end
      end

      def uri_encode(s)
        # correctly escapes spaces, unlike CGI.escape, see ruby-amqp/rabbitmq_http_api_client#28
        URI.escape(s, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
      end

      def decode_resource(response)
        Hashie::Mash.new(response.body)
      end

      def decode_resource_collection(response)
        response.body.map { |i| Hashie::Mash.new(i) }
      end
    end # Client
  end # HTTP
end # RabbitMQ
