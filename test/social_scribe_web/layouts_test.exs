defmodule SocialScribeWeb.LayoutsTest do
  use SocialScribeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures

  test "root and dashboard layouts are used for live dashboard pages", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    {:ok, _view, html} = live(conn, ~p"/dashboard")
    assert html =~ "Upcoming Meetings" or html =~ "dashboard"
  end

  describe "Layouts module" do
    test "layout_names/0 returns layout names" do
      assert SocialScribeWeb.Layouts.layout_names() == ["root", "app", "dashboard"]
    end
  end

  describe "Layouts template functions" do
    test "root layout renders with inner_content" do
      assigns = %{inner_content: {:safe, "<div>inner</div>"}, page_title: "Test"}
      html = Phoenix.HTML.Safe.to_iodata(SocialScribeWeb.Layouts.root(assigns)) |> IO.iodata_to_binary()
      assert html =~ "lang=\"en\""
      assert html =~ "SocialScribe"
      assert html =~ "inner"
    end

    test "app layout renders with inner_content and flash" do
      assigns = %{inner_content: {:safe, "<p>content</p>"}, flash: %{}}
      html = Phoenix.HTML.Safe.to_iodata(SocialScribeWeb.Layouts.app(assigns)) |> IO.iodata_to_binary()
      assert html =~ "content"
    end

    test "dashboard layout renders with inner_content, current_user and current_path" do
      user = user_fixture()
      assigns = %{
        inner_content: {:safe, "<p>main</p>"},
        flash: %{},
        current_user: user,
        current_path: ~p"/dashboard"
      }
      html = Phoenix.HTML.Safe.to_iodata(SocialScribeWeb.Layouts.dashboard(assigns)) |> IO.iodata_to_binary()
      assert html =~ "main"
      assert html =~ user.email
      assert html =~ "social scribe"
    end
  end
end
