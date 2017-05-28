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
