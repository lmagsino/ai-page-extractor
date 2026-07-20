require "test_helper"

class RobotsPolicyTest < ActiveSupport::TestCase
  def policy(txt, ua = "AIPageExtractor")
    RobotsPolicy.new(txt, ua)
  end

  test "allows everything when there are no rules" do
    assert policy("").allowed?("/anything")
  end

  test "honors a Disallow under the wildcard group" do
    txt = "User-agent: *\nDisallow: /private"
    assert_not policy(txt).allowed?("/private/data")
    assert policy(txt).allowed?("/public")
  end

  test "empty Disallow means allow all" do
    assert policy("User-agent: *\nDisallow:").allowed?("/anything")
  end

  test "Allow overrides a broader Disallow via longest match" do
    txt = "User-agent: *\nDisallow: /admin\nAllow: /admin/public"
    assert_not policy(txt).allowed?("/admin/secret")
    assert policy(txt).allowed?("/admin/public/page")
  end

  test "a group matching our user-agent takes precedence over the wildcard group" do
    txt = <<~ROBOTS
      User-agent: *
      Disallow: /

      User-agent: AIPageExtractor
      Disallow: /nope
    ROBOTS
    # Our specific group only disallows /nope, so /elsewhere is allowed even
    # though the * group disallows everything.
    assert policy(txt).allowed?("/elsewhere")
    assert_not policy(txt).allowed?("/nope/x")
  end

  test "ignores comments and unknown directives" do
    txt = "# a comment\nSitemap: http://x/s.xml\nUser-agent: *\nCrawl-delay: 5\nDisallow: /x"
    assert_not policy(txt).allowed?("/x")
    assert policy(txt).allowed?("/y")
  end

  test "class-level allowed? fails open when robots.txt is unreachable" do
    uri = URI.parse("http://example.com/page")
    stub_class_method(RobotsPolicy, :fetch_robots, ->(_uri) { nil }) do
      assert RobotsPolicy.allowed?(uri)
    end
  end

  test "class-level allowed? applies fetched rules" do
    uri = URI.parse("http://example.com/private/x")
    stub_class_method(RobotsPolicy, :fetch_robots, ->(_uri) { "User-agent: *\nDisallow: /private" }) do
      assert_not RobotsPolicy.allowed?(uri)
    end
  end
end
