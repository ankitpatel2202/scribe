defmodule Ueberauth.Strategy.Hubspot.OAuthTest do
  use ExUnit.Case, async: false

  alias Ueberauth.Strategy.Hubspot.OAuth

  @config [
    client_id: "test_client_id",
    client_secret: "test_client_secret"
  ]

  setup do
    Application.put_env(:ueberauth, Ueberauth.Strategy.Hubspot.OAuth, @config)
    on_exit(fn ->
      Application.delete_env(:ueberauth, Ueberauth.Strategy.Hubspot.OAuth)
    end)
    :ok
  end

  describe "client/1" do
    test "returns an OAuth2.Client struct" do
      client = OAuth.client()
      assert %OAuth2.Client{} = client
      assert client.client_id == "test_client_id"
      assert client.client_secret == "test_client_secret"
    end
  end

  describe "authorize_url!/2" do
    test "returns a HubSpot authorize URL" do
      url = OAuth.authorize_url!([])
      assert url =~ "app.hubspot.com"
      assert url =~ "oauth"
      assert url =~ "authorize"
    end

    test "includes scope and redirect_uri when given" do
      params = [scope: "contacts", redirect_uri: "https://app.example.com/callback"]
      url = OAuth.authorize_url!(params)
      assert url =~ "contacts"
      assert url =~ "app.example.com"
    end
  end

  describe "get_token_info/1" do
    test "returns token info on 200" do
      Tesla.Mock.mock(fn %{url: url, method: :get} ->
        assert url =~ "access-tokens/"
        {:ok, %Tesla.Env{status: 200, body: %{"user" => "user@example.com", "hub_id" => "123"}}}
      end)

      assert {:ok, body} = OAuth.get_token_info("some_access_token")
      assert body["user"] == "user@example.com"
      assert body["hub_id"] == "123"
    end

    test "returns error on non-200 status" do
      Tesla.Mock.mock(fn %{method: :get} ->
        {:ok, %Tesla.Env{status: 401, body: %{"message" => "Invalid token"}}}
      end)

      assert {:error, msg} = OAuth.get_token_info("bad_token")
      assert msg =~ "401"
      assert msg =~ "Invalid token"
    end

    test "returns error on HTTP failure" do
      Tesla.Mock.mock(fn %{method: :get} ->
        {:error, :timeout}
      end)

      assert {:error, msg} = OAuth.get_token_info("token")
      assert msg =~ "timeout"
    end
  end
end
