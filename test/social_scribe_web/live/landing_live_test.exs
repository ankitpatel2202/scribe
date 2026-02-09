defmodule SocialScribeWeb.LandingLiveTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Landing page" do
    test "renders landing content", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Turn Meetings into"
      assert html =~ "Masterpieces"
      assert html =~ "Get Started for Free"
      assert html =~ "/auth/google"
    end
  end
end
