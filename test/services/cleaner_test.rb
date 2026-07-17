require "test_helper"

class CleanerTest < ActiveSupport::TestCase
  test "strips noise selectors" do
    html = <<~HTML
      <html><head><style>.x{}</style></head>
      <body>
        <nav>menu</nav>
        <script>alert(1)</script>
        <h1>Real Title</h1>
        <p>Keep this paragraph.</p>
        <footer>copyright</footer>
      </body></html>
    HTML
    result = Cleaner.call(html)

    assert_includes result.text, "Real Title"
    assert_includes result.text, "Keep this paragraph."
    assert_not_includes result.text, "alert(1)"
    assert_not_includes result.text, "menu"
    assert_not_includes result.text, "copyright"
  end

  test "converts headings and links to markdown" do
    result = Cleaner.call('<h1>Hi</h1><a href="/x">link</a>')
    assert_includes result.text, "# Hi"
    assert_includes result.text, "[link](/x)"
  end

  test "collapses runs of blank lines" do
    result = Cleaner.call("<p>a</p>\n\n\n\n\n<p>b</p>")
    assert_not_includes result.text, "\n\n\n"
  end

  test "truncates content longer than MAX_CHARS and flags it" do
    long = "<p>#{"x" * (Cleaner::MAX_CHARS + 500)}</p>"
    result = Cleaner.call(long)

    assert_equal Cleaner::MAX_CHARS, result.text.length
    assert result.truncated
  end

  test "does not flag truncation for short content" do
    result = Cleaner.call("<p>short</p>")
    assert_not result.truncated
    assert_equal "short", result.text
  end

  test "handles empty and nil html without raising" do
    assert_equal "", Cleaner.call("").text
    assert_equal "", Cleaner.call(nil).text
    assert_not Cleaner.call(nil).truncated
  end
end
