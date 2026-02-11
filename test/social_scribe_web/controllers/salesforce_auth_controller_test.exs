defmodule SocialScribeWeb.SalesforceAuthControllerTest do
  use SocialScribeWeb.ConnCase, async: false

  import SocialScribe.AccountsFixtures
  import Plug.Conn

  @salesforce_config [
    :salesforce_client_id,
    :salesforce_client_secret,
    :salesforce_redirect_uri,
    :salesforce_auth_base_url
  ]

  setup do
    Application.put_env(:social_scribe, :salesforce_client_id, "test_client_id")
    Application.put_env(:social_scribe, :salesforce_client_secret, "test_client_secret")
    Application.put_env(:social_scribe, :salesforce_redirect_uri, "https://app.example.com/auth/salesforce/callback")
    Application.put_env(:social_scribe, :salesforce_auth_base_url, "https://login.salesforce.com")

    on_exit(fn ->
      for key <- @salesforce_config do
        Application.delete_env(:social_scribe, key)
      end
    end)

    :ok
  end

  describe "GET /dashboard/auth/salesforce (request)" do
    test "redirects to Salesforce when logged in", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/dashboard/auth/salesforce")

      assert redirected_to(conn) =~ "salesforce.com"
      assert redirected_to(conn) =~ "authorize"
      assert redirected_to(conn) =~ "code_challenge"
      assert redirected_to(conn) =~ "client_id=test_client_id"
    end

    test "stores state, user_id and code_verifier in session", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/dashboard/auth/salesforce")

      assert get_session(conn, :salesforce_oauth_state)
      assert get_session(conn, :salesforce_oauth_user_id) == user.id
      assert get_session(conn, :salesforce_oauth_code_verifier)
    end

    test "redirects to login when not logged in" do
      conn = build_conn()
      conn = get(conn, ~p"/dashboard/auth/salesforce")
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "GET /dashboard/auth/salesforce/callback (callback)" do
    defp conn_with_salesforce_session(conn, user, state) do
      code_verifier = "test-code-verifier"
      conn
      |> log_in_user(user)
      |> put_session(:salesforce_oauth_state, state)
      |> put_session(:salesforce_oauth_user_id, user.id)
      |> put_session(:salesforce_oauth_code_verifier, code_verifier)
    end

    test "redirects with error when no code in params", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/dashboard/auth/salesforce/callback")

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "code"
    end

    test "success: exchanges code for token and redirects to settings", %{conn: conn} do
      Tesla.Mock.mock(fn %{method: :post, url: url} ->
        assert url =~ "token"
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "access_token" => "at",
             "refresh_token" => "rt",
             "instance_url" => "https://my.salesforce.com",
             "id" => "https://login.salesforce.com/id/00Dxx/005yy"
           }
         }}
      end)

      user = user_fixture()
      state = "valid-state"
      conn = conn_with_salesforce_session(conn, user, state)
      conn = get(conn, ~p"/dashboard/auth/salesforce/callback" <> "?" <> URI.encode_query(%{"code" => "auth-code", "state" => state}))

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Salesforce connected"
      assert get_session(conn, :salesforce_oauth_state) == nil
      assert get_session(conn, :salesforce_oauth_user_id) == nil
      assert get_session(conn, :salesforce_oauth_code_verifier) == nil
    end

    test "invalid state: redirects with error and does not clear session", %{conn: conn} do
      user = user_fixture()
      conn = conn_with_salesforce_session(conn, user, "stored-state")
      conn = get(conn, ~p"/dashboard/auth/salesforce/callback" <> "?" <> URI.encode_query(%{"code" => "code", "state" => "wrong-state"}))

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid OAuth state"
    end

    test "session expired: no user_id in session redirects with error", %{conn: conn} do
      user = user_fixture()
      state = "some-state"
      conn =
        conn
        |> log_in_user(user)
        |> put_session(:salesforce_oauth_state, state)
        |> put_session(:salesforce_oauth_code_verifier, "verifier")
      # Intentionally omit salesforce_oauth_user_id

      conn = get(conn, ~p"/dashboard/auth/salesforce/callback" <> "?" <> URI.encode_query(%{"code" => "code", "state" => state}))

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Session expired"
    end

    test "user not found: redirects with error", %{conn: conn} do
      state = "state-123"
      conn =
        conn
        |> log_in_user(user_fixture())
        |> put_session(:salesforce_oauth_state, state)
        |> put_session(:salesforce_oauth_user_id, 99_999_999)
        |> put_session(:salesforce_oauth_code_verifier, "v")

      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, %Tesla.Env{status: 200, body: %{"access_token" => "at", "instance_url" => "https://x.com", "id" => "https://login.salesforce.com/id/00D/005"}}}
      end)

      conn = get(conn, ~p"/dashboard/auth/salesforce/callback" <> "?" <> URI.encode_query(%{"code" => "c", "state" => state}))

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "User not found"
    end

    test "token exchange failure: redirects with error", %{conn: conn} do
      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, %Tesla.Env{status: 400, body: %{"error" => "invalid_grant"}}}
      end)

      user = user_fixture()
      state = "state-token-fail"
      conn = conn_with_salesforce_session(conn, user, state)

      ref = make_ref()
      _ = ExUnit.CaptureLog.capture_log(fn ->
        send(self(), {ref, get(conn, ~p"/dashboard/auth/salesforce/callback" <> "?" <> URI.encode_query(%{"code" => "bad-code", "state" => state}))})
      end)
      conn = receive do
        {^ref, c} -> c
      end

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Could not connect to Salesforce"
    end

    test "token exchange http error: redirects with error", %{conn: conn} do
      Tesla.Mock.mock(fn %{method: :post} ->
        {:error, :timeout}
      end)

      user = user_fixture()
      state = "state-http-fail"
      conn = conn_with_salesforce_session(conn, user, state)

      ref = make_ref()
      _ = ExUnit.CaptureLog.capture_log(fn ->
        send(self(), {ref, get(conn, ~p"/dashboard/auth/salesforce/callback" <> "?" <> URI.encode_query(%{"code" => "code", "state" => state}))})
      end)
      conn = receive do
        {^ref, c} -> c
      end

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Could not connect to Salesforce"
    end

    test "success with token response without refresh_token", %{conn: conn} do
      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "access_token" => "at-only",
             "instance_url" => "https://cs.salesforce.com",
             "id" => "https://login.salesforce.com/id/00D/005"
           }
         }}
      end)

      user = user_fixture()
      state = "state-no-refresh"
      conn = conn_with_salesforce_session(conn, user, state)
      conn = get(conn, ~p"/dashboard/auth/salesforce/callback" <> "?" <> URI.encode_query(%{"code" => "code", "state" => state}))

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Salesforce connected"
    end
  end
end
