defmodule Ueberauth.Strategy.HubspotTest do
  use SocialScribeWeb.ConnCase, async: false

  alias Ueberauth.Strategy.Hubspot
  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra

  describe "handle_callback!/1" do
    test "sets errors when code is missing" do
      conn =
        build_conn(:get, "/auth/hubspot/callback", %{})
        |> Plug.Conn.put_private(:ueberauth_state_param, "state")
        |> Plug.Conn.put_private(:ueberauth_request_options, %{
          strategy_name: "hubspot",
          strategy: Hubspot
        })

      conn = Hubspot.handle_callback!(conn)
      assert conn.assigns[:ueberauth_failure]
      failure = conn.assigns.ueberauth_failure
      assert length(failure.errors) == 1
      assert hd(failure.errors).message == "No code received"
    end
  end

  describe "uid/1" do
    test "returns hub_id from hubspot_user" do
      conn =
        build_conn(:get, "/auth/hubspot/callback", %{})
        |> Plug.Conn.put_private(:ueberauth_request_options, %{options: [uid_field: :hub_id]})
        |> Plug.Conn.put_private(:hubspot_user, %{"hub_id" => "12345"})

      assert Hubspot.uid(conn) == "12345"
    end
  end

  describe "credentials/1" do
    test "returns Credentials from hubspot_token" do
      expires_at = DateTime.utc_now() |> DateTime.add(3600, :second)
      token = %OAuth2.AccessToken{
        access_token: "at",
        refresh_token: "rt",
        expires_at: expires_at,
        token_type: "Bearer",
        other_params: %{"scope" => "contacts oauth"}
      }

      conn =
        build_conn(:get, "/auth/hubspot/callback", %{})
        |> Plug.Conn.put_private(:hubspot_token, token)

      creds = Hubspot.credentials(conn)
      assert %Credentials{} = creds
      assert creds.token == "at"
      assert creds.refresh_token == "rt"
      assert creds.token_type == "Bearer"
      assert "contacts" in creds.scopes
      assert "oauth" in creds.scopes
    end

    test "handles token with empty or nil scope" do
      token = %OAuth2.AccessToken{
        access_token: "at",
        refresh_token: nil,
        expires_at: nil,
        token_type: "Bearer",
        other_params: %{}
      }

      conn =
        build_conn(:get, "/auth/hubspot/callback", %{})
        |> Plug.Conn.put_private(:hubspot_token, token)

      creds = Hubspot.credentials(conn)
      assert creds.token == "at"
      assert creds.scopes in [[], [""]]
    end
  end

  describe "info/1" do
    test "returns Info from hubspot_user" do
      conn =
        build_conn(:get, "/auth/hubspot/callback", %{})
        |> Plug.Conn.put_private(:hubspot_user, %{"user" => "user@hubspot.com"})

      info = Hubspot.info(conn)
      assert %Info{} = info
      assert info.email == "user@hubspot.com"
      assert info.name == "user@hubspot.com"
    end
  end

  describe "extra/1" do
    test "returns Extra with raw token and user" do
      token = %OAuth2.AccessToken{access_token: "at"}
      user = %{"hub_id" => "1", "user" => "u@example.com"}

      conn =
        build_conn(:get, "/auth/hubspot/callback", %{})
        |> Plug.Conn.put_private(:hubspot_token, token)
        |> Plug.Conn.put_private(:hubspot_user, user)

      extra = Hubspot.extra(conn)
      assert %Extra{} = extra
      assert extra.raw_info.token == token
      assert extra.raw_info.user == user
    end
  end

  describe "handle_cleanup!/1" do
    test "clears hubspot_token and hubspot_user" do
      conn =
        build_conn(:get, "/auth/hubspot/callback", %{})
        |> Plug.Conn.put_private(:hubspot_token, %OAuth2.AccessToken{})
        |> Plug.Conn.put_private(:hubspot_user, %{})

      conn = Hubspot.handle_cleanup!(conn)
      assert conn.private[:hubspot_token] == nil
      assert conn.private[:hubspot_user] == nil
    end
  end
end
