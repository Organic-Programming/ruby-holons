# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require_relative "../lib/holons"

class HolonsTest < Minitest::Test
  def test_scheme
    assert_equal "tcp", Holons::Transport.scheme("tcp://:9090")
    assert_equal "unix", Holons::Transport.scheme("unix:///tmp/x.sock")
    assert_equal "stdio", Holons::Transport.scheme("stdio://")
  end

  def test_default_uri
    assert_equal "tcp://:9090", Holons::Transport::DEFAULT_URI
  end

  def test_tcp_listen
    srv = Holons::Transport.listen("tcp://127.0.0.1:0")
    assert srv.local_address.ip_port > 0
    srv.close
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
