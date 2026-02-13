# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "securerandom"
require "tempfile"
require "timeout"
require_relative "../lib/holons"

class HolonsTest < Minitest::Test
  def test_scheme
    assert_equal "tcp", Holons::Transport.scheme("tcp://:9090")
    assert_equal "unix", Holons::Transport.scheme("unix:///tmp/x.sock")
    assert_equal "stdio", Holons::Transport.scheme("stdio://")
    assert_equal "mem", Holons::Transport.scheme("mem://")
    assert_equal "ws", Holons::Transport.scheme("ws://127.0.0.1:8080/grpc")
    assert_equal "wss", Holons::Transport.scheme("wss://example.com:443/grpc")
  end

  def test_default_uri
    assert_equal "tcp://:9090", Holons::Transport::DEFAULT_URI
  end

  def test_tcp_listen
    listener = Holons::Transport.listen("tcp://127.0.0.1:0")
    assert_instance_of Holons::Transport::Listener::Tcp, listener
    assert listener.socket.local_address.ip_port > 0
    listener.socket.close
  end

  def test_parse_uri_wss_defaults
    parsed = Holons::Transport.parse_uri("wss://example.com:8443")
    assert_equal "wss", parsed.scheme
    assert_equal "example.com", parsed.host
    assert_equal 8443, parsed.port
    assert_equal "/grpc", parsed.path
    assert parsed.secure
  end

  def test_stdio_and_mem_variants
    stdio = Holons::Transport.listen("stdio://")
    mem = Holons::Transport.listen("mem://")

    assert_instance_of Holons::Transport::Listener::Stdio, stdio
    assert_instance_of Holons::Transport::Listener::Mem, mem
    assert_equal "stdio://", stdio.address
    assert_equal "mem://", mem.address
  end

  def test_runtime_tcp_roundtrip
    listener = Holons::Transport.listen("tcp://127.0.0.1:0")
    tcp = listener
    accepted = nil

    accept_thread = Thread.new do
      accepted = Holons::Transport.accept(tcp)
    end

    client = TCPSocket.new("127.0.0.1", tcp.socket.local_address.ip_port)
    accept_thread.join

    client.write("ping")
    payload = Holons::Transport.conn_read(accepted, 4)
    assert_equal "ping", payload

    Holons::Transport.close_connection(accepted)
    client.close
    tcp.socket.close
  end

  def test_runtime_stdio_single_accept
    stdio = Holons::Transport.listen("stdio://")
    conn = Holons::Transport.accept(stdio)
    assert_equal "stdio", conn.scheme
    Holons::Transport.close_connection(conn)
    assert_raises(RuntimeError) { Holons::Transport.accept(stdio) }
  end

  def test_runtime_mem_roundtrip
    mem = Holons::Transport.listen("mem://ruby-test")
    client = Holons::Transport.mem_dial(mem)
    server = Holons::Transport.accept(mem)

    Holons::Transport.conn_write(client, "mem")
    payload = Holons::Transport.conn_read(server, 3)
    assert_equal "mem", payload

    Holons::Transport.close_connection(server)
    Holons::Transport.close_connection(client)
  end

  def test_ws_runtime_unsupported
    ws = Holons::Transport.listen("ws://127.0.0.1:8080/grpc")
    assert_raises(RuntimeError) { Holons::Transport.accept(ws) }
  end

  def test_ws_variant
    ws = Holons::Transport.listen("ws://127.0.0.1:8080/holon")
    assert_instance_of Holons::Transport::Listener::WS, ws
    assert_equal "127.0.0.1", ws.host
    assert_equal 8080, ws.port
    assert_equal "/holon", ws.path
    refute ws.secure
  end

  def test_unsupported_uri
    assert_raises(ArgumentError) { Holons::Transport.listen("ftp://host") }
  end

  def test_parse_flags_listen
    assert_equal "tcp://:8080",
      Holons::Serve.parse_flags(["--listen", "tcp://:8080"])
  end

  def test_parse_flags_port
    assert_equal "tcp://:3000",
      Holons::Serve.parse_flags(["--port", "3000"])
  end

  def test_parse_flags_default
    assert_equal Holons::Transport::DEFAULT_URI,
      Holons::Serve.parse_flags([])
  end

  def test_parse_holon
    tmp = Tempfile.new(["holon", ".md"])
    tmp.write("---\nuuid: \"abc-123\"\ngiven_name: \"test\"\n" \
              "family_name: \"Test\"\nlang: \"ruby\"\n---\n# test\n")
    tmp.flush

    id = Holons::Identity.parse_holon(tmp.path)
    assert_equal "abc-123", id.uuid
    assert_equal "test", id.given_name
    assert_equal "ruby", id.lang

    tmp.close!
  end

  def test_parse_missing_frontmatter
    tmp = Tempfile.new(["nofm", ".md"])
    tmp.write("# No frontmatter\n")
    tmp.flush
    assert_raises(RuntimeError) { Holons::Identity.parse_holon(tmp.path) }
    tmp.close!
  end
end

class HolonRPCTest < Minitest::Test
  def test_echo_roundtrip_with_go_helper
    with_go_helper("echo") do |url|
      client = Holons::HolonRPCClient.new(
        heartbeat_interval_ms: 250,
        heartbeat_timeout_ms: 250,
        reconnect_min_delay_ms: 100,
        reconnect_max_delay_ms: 400
      )

      client.connect(url)
      out = client.invoke("echo.v1.Echo/Ping", { "message" => "hello" })
      assert_equal "hello", out["message"]
      client.close
    end
  end

  def test_register_handles_server_calls
    with_go_helper("echo") do |url|
      client = Holons::HolonRPCClient.new(
        heartbeat_interval_ms: 250,
        heartbeat_timeout_ms: 250,
        reconnect_min_delay_ms: 100,
        reconnect_max_delay_ms: 400
      )

      client.register("client.v1.Client/Hello") do |params|
        { "message" => "hello #{params["name"] || ""}" }
      end

      client.connect(url)
      out = client.invoke("echo.v1.Echo/CallClient", {})
      assert_equal "hello go", out["message"]
      client.close
    end
  end

  def test_reconnect_and_heartbeat
    with_go_helper("drop-once") do |url|
      client = Holons::HolonRPCClient.new(
        heartbeat_interval_ms: 200,
        heartbeat_timeout_ms: 200,
        reconnect_min_delay_ms: 100,
        reconnect_max_delay_ms: 400
      )

      client.connect(url)
      first = client.invoke("echo.v1.Echo/Ping", { "message" => "first" })
      assert_equal "first", first["message"]

      sleep 0.7

      second = invoke_eventually(client, "echo.v1.Echo/Ping", { "message" => "second" })
      assert_equal "second", second["message"]

      hb = invoke_eventually(client, "echo.v1.Echo/HeartbeatCount", {})
      assert hb["count"].to_i >= 1
      client.close
    end
  end

  private

  def invoke_eventually(client, method, params)
    last_error = nil
    40.times do
      begin
        return client.invoke(method, params)
      rescue StandardError => e
        last_error = e
        sleep 0.12
      end
    end
    raise(last_error || RuntimeError.new("invoke eventually failed"))
  end

  def with_go_helper(mode)
    sdk_dir = find_sdk_dir
    go_dir = File.join(sdk_dir, "go-holons")
    fixture = File.join(__dir__, "fixtures", "go_holonrpc_helper.go")
    helper = File.join(go_dir, "tmp-holonrpc-#{SecureRandom.uuid}.go")
    File.write(helper, File.read(fixture))

    go_bin = resolve_go_binary
    stdin, stdout, stderr, wait_thr =
      Open3.popen3(go_bin, "run", helper, mode, chdir: go_dir)

    begin
      url = nil
      Timeout.timeout(20) do
        url = stdout.gets&.strip
      end
      raise "Go helper did not output URL: #{stderr.read}" if url.nil? || url.empty?

      yield(url)
    ensure
      stdin.close unless stdin.closed?
      begin
        Process.kill("TERM", wait_thr.pid)
      rescue StandardError
        nil
      end
      begin
        Timeout.timeout(5) { wait_thr.value }
      rescue StandardError
        begin
          Process.kill("KILL", wait_thr.pid)
        rescue StandardError
          nil
        end
      end
      stdout.close unless stdout.closed?
      stderr.close unless stderr.closed?
      File.delete(helper) if File.exist?(helper)
    end
  end

  def find_sdk_dir
    dir = Dir.pwd
    12.times do
      candidate = File.join(dir, "go-holons")
      return dir if Dir.exist?(candidate)

      parent = File.dirname(dir)
      break if parent == dir

      dir = parent
    end
    raise "unable to locate sdk directory containing go-holons"
  end

  def resolve_go_binary
    preferred = "/Users/bpds/go/go1.25.1/bin/go"
    File.executable?(preferred) ? preferred : "go"
  end
end
