defmodule SocialScribeWeb.AuthControllerTest do
  use SocialScribeWeb.ConnCase, async: true

  describe "GET /auth/:provider (request)" do
    test "redirects to provider for google", %{conn: conn} do
      conn = get(conn, ~p"/auth/google")
      # Ueberauth redirects to Google OAuth
      assert redirected_to(conn) =~ "accounts.google.com"
    end
  end

  describe "GET /auth/:provider/callback (callback)" do
    test "redirects with error when no ueberauth auth", %{conn: conn} do
      conn = get(conn, ~p"/auth/google/callback")
      assert redirected_to(conn) == ~p"/"
    end
  end
end
