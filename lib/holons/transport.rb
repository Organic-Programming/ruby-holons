# frozen_string_literal: true

require "socket"

module Holons
  module Transport
    DEFAULT_URI = "tcp://:9090"

    ParsedURI = Struct.new(:raw, :scheme, :host, :port, :path, :secure, keyword_init: true)

    module Listener
      Tcp = Struct.new(:socket)
      Unix = Struct.new(:socket, :path)
      Stdio = Struct.new(:address)
      Mem = Struct.new(:address)
      WS = Struct.new(:host, :port, :path, :secure, keyword_init: true)
    end

    # Extract scheme from a transport URI.
    def self.scheme(uri)
      idx = uri.index("://")
      idx ? uri[0...idx] : uri
    end

    # Parse a transport URI into a normalized structure.
    def self.parse_uri(uri)
      s = scheme(uri)

      case s
      when "tcp"
        raise ArgumentError, "invalid tcp URI: #{uri}" unless uri.start_with?("tcp://")

        host, port = split_host_port(uri.delete_prefix("tcp://"), 9090)
        ParsedURI.new(raw: uri, scheme: "tcp", host: host, port: port, path: nil, secure: false)
      when "unix"
        raise ArgumentError, "invalid unix URI: #{uri}" unless uri.start_with?("unix://")

        path = uri.delete_prefix("unix://")
        raise ArgumentError, "invalid unix URI: #{uri}" if path.empty?

        ParsedURI.new(raw: uri, scheme: "unix", host: nil, port: nil, path: path, secure: false)
      when "stdio"
        ParsedURI.new(raw: "stdio://", scheme: "stdio", host: nil, port: nil, path: nil, secure: false)
      when "mem"
        ParsedURI.new(raw: uri.start_with?("mem://") ? uri : "mem://", scheme: "mem", host: nil, port: nil, path: nil,
                      secure: false)
      when "ws", "wss"
        secure = s == "wss"
        prefix = secure ? "wss://" : "ws://"
        raise ArgumentError, "invalid ws URI: #{uri}" unless uri.start_with?(prefix)

        trimmed = uri.delete_prefix(prefix)
        addr, path = trimmed.split("/", 2)
        path = path.nil? || path.empty? ? "/grpc" : "/#{path}"
        host, port = split_host_port(addr, secure ? 443 : 80)
        ParsedURI.new(raw: uri, scheme: s, host: host, port: port, path: path, secure: secure)
      else
        raise ArgumentError, "unsupported transport URI: #{uri}"
      end
    end

    # Parse a transport URI and return a listener variant.
    def self.listen(uri)
      parsed = parse_uri(uri)

      case parsed.scheme
      when "tcp"
        Listener::Tcp.new(listen_tcp(parsed))
      when "unix"
        Listener::Unix.new(listen_unix(parsed.path), parsed.path)
      when "stdio"
        Listener::Stdio.new("stdio://")
      when "mem"
        Listener::Mem.new("mem://")
      when "ws", "wss"
        Listener::WS.new(
          host: parsed.host || "0.0.0.0",
          port: parsed.port || (parsed.secure ? 443 : 80),
          path: parsed.path || "/grpc",
          secure: parsed.secure
        )
      else
        raise ArgumentError, "unsupported transport URI: #{uri}"
      end
    end

    def self.listen_tcp(parsed)
      host = parsed.host || "0.0.0.0"
      port = parsed.port || 9090
      TCPServer.new(host, port)
    end

    def self.listen_unix(path)
      File.delete(path) if File.exist?(path)
      UNIXServer.new(path)
    end

    def self.split_host_port(addr, default_port)
      return ["0.0.0.0", default_port] if addr.empty?

      host, separator, port_text = addr.rpartition(":")
      return [addr, default_port] if separator.empty?

      host = "0.0.0.0" if host.empty?
      port = port_text.empty? ? default_port : Integer(port_text, 10)
      [host, port]
    end

    private_class_method :listen_tcp, :listen_unix, :split_host_port
  end
end
