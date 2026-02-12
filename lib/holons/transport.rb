# frozen_string_literal: true

require "socket"

module Holons
  module Transport
    DEFAULT_URI = "tcp://:9090"

    # Extract scheme from a transport URI.
    def self.scheme(uri)
      idx = uri.index("://")
      idx ? uri[0...idx] : uri
    end

    # Parse a transport URI and return a bound server socket.
    def self.listen(uri)
      case uri
      when /\Atcp:\/\//
        listen_tcp(uri.sub("tcp://", ""))
      when /\Aunix:\/\//
        listen_unix(uri.sub("unix://", ""))
      else
        raise ArgumentError, "unsupported transport URI: #{uri}"
      end
    end

    def self.listen_tcp(addr)
      host, port = addr.rpartition(":").values_at(0, 2)
      host = "0.0.0.0" if host.empty?
      TCPServer.new(host, port.to_i)
    end

    def self.listen_unix(path)
      File.delete(path) if File.exist?(path)
      UNIXServer.new(path)
    end

    private_class_method :listen_tcp, :listen_unix
  end
end
