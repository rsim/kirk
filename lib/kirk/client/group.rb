require 'uri'

module Kirk
  class Client
    class Group
      attr_reader :client, :host, :options, :responses

      def initialize(client = Client.new, options = {})
        @options = options
        @client  = client
        @queue   = LinkedBlockingQueue.new

        @requests_count = 0
        @responses      = []

        if @options[:host]
          @host = @options.delete(:host).chomp('/')
          @host = "http://#{@host}" unless @host =~ /^https?:\/\//
        end
      end

      def block?
        options.key?(:block) ? options[:block] : true
      end

      def start
        ret = yield self
        join if block?
        ret
      end

      def join
        get_responses
      end

      def complete(&blk)
        @complete = blk if blk
        @complete
      end

      def request(method = nil, url = nil, handler = nil, body = nil, headers = {})
        request = Request.new(self, method, url, handler, body, headers)

        yield request if block_given?

        request.url URI.join(host, request.url).to_s if host
        request.validate!

        process(request)
        request
      end

      def respond(response)
        @queue.put(response)
      end

      %w/get post put delete head/.each do |method|
        class_eval <<-RUBY
          def #{method}(url, headers = nil, handler = nil)
            request(:#{method.upcase}, url, headers, handler)
          end
        RUBY
      end

      def process(request)
        @client.process(request)
        @requests_count += 1
      end

      def get_responses
        while @requests_count > 0
          if resp = @queue.poll(timeout, TimeUnit::SECONDS)
            @responses << resp
            @requests_count -= 1
          else
            raise "timed out"
          end
        end

        completed
      end

    private

      def completed
        complete.call if complete
      end

      def timeout
        @options[:timeout] || 30
      end
    end
  end
end
