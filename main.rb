require 'rack'
require 'net/http'

class Toxic
	def with_enabled
		enable!
		yield
	ensure
		disable!
	end

	def enable!
		raise NotImplementedError
	end

	def disable!
		raise NotImplementedError
	end
end

class Server
  attr_reader :port

  def initialize(port)
    @port = port
  end

  def call(env)
    ['200', { 'Content-Type' => 'text/html' }, ['success']]
  end

  def with_server
    @server = fork do
      run
    end
    sleep 1
    yield
  ensure
    Process.kill('KILL', @server)
    Process.wait
  end

  private

  def run
    Rack::Handler::WEBrick.run(self,
			       Port: port,
                               AccessLog: [],
                               Logger: WEBrick::Log.new('/dev/null'))
  end
end

class DropOutputToxic < Toxic
	attr_reader :host, :port

	def initialize(host, port)
		@host = host
		@port = port
	end

	def enable!
		`sudo iptables -I OUTPUT -p tcp -o lo --dport #{port} -j DROP`
	end

	def disable!
		`sudo iptables -D OUTPUT -p tcp -o lo --dport #{port} -j DROP`
	end
end

require "test/unit"

class DropOutputToxicTest < Test::Unit::TestCase
	def setup
		@host = '127.0.0.1'
		@port = '1234'
		@toxic = DropOutputToxic.new(@host, @port)
                @server = Server.new(@port)
	end

	def test_toxic_drops_output_and_cleans_up
		@server.with_server do
			assert can_connect_to_host?
			@toxic.with_enabled do
				refute can_connect_to_host?
			end
			assert can_connect_to_host?
		end
	end

	private

	def can_connect_to_host?
		http = Net::HTTP.new(@host, @port)
		http.open_timeout = 0.1
		http.get('/')
		true
	rescue Net::OpenTimeout
		false
	end
end
