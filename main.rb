require 'rack'
require 'net/http'
require 'test/unit'

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

  def call(_env)
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
    `iptables -I OUTPUT -p tcp -o lo --dport #{port} -j DROP`
  end

  def disable!
    `iptables -D OUTPUT -p tcp -o lo --dport #{port} -j DROP`
  end
end

class LatencyToxic < Toxic
  attr_reader :delay

  def initialize(delay)
    @delay = delay
  end

  def enable!
    `tc qdisc add dev lo root netem delay #{delay}ms`
  end

  def disable!
    `tc qdisc del dev lo root netem`
  end
end

class ToxicTest < Test::Unit::TestCase
  def setup
    @host = '127.0.0.1'
    @port = '1234'
    @server = Server.new(@port)
  end

  protected

  def can_connect_to_host?(timeout = 0.2)
    start = Time.now
    http = Net::HTTP.new(@host, @port)
    http.open_timeout = timeout
    http.get('/')
    (Time.now - start)
  rescue Net::OpenTimeout
    nil
  end

  def with_server
    @server.with_server do
      yield
    end
  end

  def with_toxic
    @toxic.with_enabled do
      yield
    end
  end
end

class DropOutputToxicTest < ToxicTest
  def setup
    super
    @toxic = DropOutputToxic.new(@host, @port)
  end

  def test_toxic_drops_output_and_cleans_up
    with_server do
      assert can_connect_to_host?
      with_toxic do
        refute can_connect_to_host?
      end
      assert can_connect_to_host?
    end
  end
end

class LatencyToxicTest < ToxicTest
  def setup
    super
    @delay = 100
    @toxic = LatencyToxic.new(@delay)
  end

  def test_toxic_adds_latency
    with_server do
      assert can_connect_to_host?
      with_toxic do
        ms = @delay / 1000.0
        assert can_connect_to_host?(ms * 2.5) > ms
      end
      assert can_connect_to_host?
    end
  end
end
