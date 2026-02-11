defmodule SocialScribeWeb.AuthControllerTest do
  use SocialScribeWeb.ConnCase, async: true

  import SocialScribe.AccountsFixtures
  import Mox

  setup :verify_on_exit!

  defp google_auth(attrs \\ %{}) do
    struct(
      Ueberauth.Auth,
      Map.merge(
        %{
          provider: :google,
          uid: "google-uid-#{System.unique_integer([:positive])}",
          info: %Ueberauth.Auth.Info{
            email: "oauth@example.com",
            name: "OAuth User"
          },
          credentials: %Ueberauth.Auth.Credentials{
            token: "token",
            refresh_token: "refresh",
            expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()
          }
        },
        attrs
      )
    )
  end

  defp linkedin_auth(attrs \\ %{}) do
    struct(
      Ueberauth.Auth,
      Map.merge(
        %{
          provider: :linkedin,
          uid: "linkedin-uid-#{System.unique_integer([:positive])}",
          info: %Ueberauth.Auth.Info{email: "linkedin@example.com"},
          credentials: %Ueberauth.Auth.Credentials{
            token: "token",
            expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()
          },
          extra: %{raw_info: %{user: %{"sub" => "li-sub-#{System.unique_integer([:positive])}"}}}
        },
        attrs
      )
    )
  end

  defp facebook_auth(attrs \\ %{}) do
    struct(
      Ueberauth.Auth,
      Map.merge(
        %{
          provider: :facebook,
          uid: "fb-uid-#{System.unique_integer([:positive])}",
          info: %Ueberauth.Auth.Info{email: "fb@example.com"},
          credentials: %Ueberauth.Auth.Credentials{
            token: "token",
            expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()
          }
        },
        attrs
      )
    )
  end

  defp hubspot_auth(attrs \\ %{}) do
    struct(
      Ueberauth.Auth,
      Map.merge(
        %{
          provider: :hubspot,
          uid: "hub-#{System.unique_integer([:positive])}",
          info: %Ueberauth.Auth.Info{email: "hub@example.com"},
          credentials: %Ueberauth.Auth.Credentials{
            token: "token",
            refresh_token: "refresh",
            expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()
          }
        },
        attrs
      )
    )
  end

  defp conn_with_oauth(conn, auth, opts \\ []) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Phoenix.Controller.fetch_flash([])
    |> assign(:ueberauth_auth, auth)
    |> then(fn c ->
      if user = Keyword.get(opts, :current_user), do: assign(c, :current_user, user), else: c
    end)
  end

  describe "GET /auth/:provider (request)" do
    test "redirects to provider for google", %{conn: conn} do
      conn = get(conn, ~p"/auth/google")
      assert redirected_to(conn) =~ "accounts.google.com"
    end

  end

  describe "GET /auth/:provider/callback (callback)" do
    @describetag :capture_log

    test "redirects with error when no ueberauth auth", %{conn: conn} do
      conn = get(conn, ~p"/auth/google/callback")
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "error signing you in"
    end

    test "Google callback with logged-in user success", %{conn: conn} do
      user = user_fixture()
      auth = google_auth()
      conn = conn_with_oauth(conn, auth, current_user: user)
      conn = SocialScribeWeb.AuthController.callback(conn, %{"provider" => "google"})

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Google account added successfully"
    end

    test "LinkedIn callback with user success", %{conn: conn} do
      user = user_fixture()
      auth = linkedin_auth()
      conn = conn_with_oauth(conn, auth, current_user: user)
      conn = SocialScribeWeb.AuthController.callback(conn, %{"provider" => "linkedin"})

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "LinkedIn account added successfully"
    end

    test "Facebook callback with user success and fetch_user_pages", %{conn: conn} do
      stub(SocialScribe.FacebookApiMock, :fetch_user_pages, fn _uid, _token ->
        {:ok,
         [
           %{
             id: "page1",
             name: "Page 1",
             page_access_token: "pt",
             category: nil
           }
         ]}
      end)

      user = user_fixture()
      auth = facebook_auth()
      conn = conn_with_oauth(conn, auth, current_user: user)
      conn = SocialScribeWeb.AuthController.callback(conn, %{"provider" => "facebook"})

      assert redirected_to(conn) == ~p"/dashboard/settings/facebook_pages"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Facebook account added successfully"
    end

    test "HubSpot callback with user success", %{conn: conn} do
      user = user_fixture()
      auth = hubspot_auth()
      conn = conn_with_oauth(conn, auth, current_user: user)
      conn = SocialScribeWeb.AuthController.callback(conn, %{"provider" => "hubspot"})

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "HubSpot account connected successfully"
    end

    test "callback with ueberauth_auth but no current_user (Google login) creates user and logs in", %{
      conn: conn
    } do
      auth = google_auth(%{info: %Ueberauth.Auth.Info{email: "newuser@example.com"}})
      conn = conn_with_oauth(conn, auth)
      conn = SocialScribeWeb.AuthController.callback(conn, %{"provider" => "google"})

      assert redirected_to(conn) == ~p"/dashboard"
      assert get_session(conn, :user_token)
    end

    test "fallback callback when ueberauth_auth is not in assigns redirects with error", %{conn: conn} do
      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash([])
      # Do not assign ueberauth_auth so the last callback clause matches

      conn = SocialScribeWeb.AuthController.callback(conn, %{"provider" => "unknown"})

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "error signing you in"
    end
  end
end
