defmodule SocialScribeWeb.MeetingLiveIndexTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures

  describe "Meetings index" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "lists meetings for the user", %{conn: conn, user: _user} do
      _meeting = meeting_fixture()
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings")
      assert html =~ "Past Meetings"
      assert html =~ "Meetings"
    end

    test "redirects when not logged in" do
      conn = build_conn()
      conn = get(conn, ~p"/dashboard/meetings")
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end
end
