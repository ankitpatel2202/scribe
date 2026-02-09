defmodule SocialScribeWeb.SalesforceAuthControllerTest do
  use SocialScribeWeb.ConnCase, async: true

  import SocialScribe.AccountsFixtures

  describe "GET /dashboard/auth/salesforce (request)" do
    test "redirects to Salesforce when logged in", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/dashboard/auth/salesforce")
      assert redirected_to(conn) =~ "salesforce.com"
      assert redirected_to(conn) =~ "authorize"
    end

    test "redirects to login when not logged in" do
      conn = build_conn()
      conn = get(conn, ~p"/dashboard/auth/salesforce")
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "GET /dashboard/auth/salesforce/callback (callback)" do
    test "redirects with error when no code in params", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/dashboard/auth/salesforce/callback")
      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "code"
    end
  end
end
