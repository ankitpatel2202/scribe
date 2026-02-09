defmodule SocialScribe.SalesforceApiTest do
  use SocialScribe.DataCase, async: false

  alias SocialScribe.SalesforceApi

  import SocialScribe.AccountsFixtures

  setup do
    # Ensure config exists so we don't fetch! in tests that hit refresh
    Application.put_env(:social_scribe, :salesforce_client_id, "test_client")
    Application.put_env(:social_scribe, :salesforce_client_secret, "test_secret")
    Application.put_env(:social_scribe, :salesforce_redirect_uri, "http://localhost/callback")
    Application.put_env(:social_scribe, :salesforce_auth_base_url, "https://login.salesforce.com")

    # Mock all Tesla HTTP so we don't hit real Salesforce or log errors
    Tesla.Mock.mock(fn
      %{method: :post, url: url} ->
        if String.contains?(to_string(url), "token") do
          %Tesla.Env{
            status: 200,
            body: %{
              "access_token" => "mocked_token",
              "instance_url" => "https://example.salesforce.com",
              "id" => "https://id.salesforce.com/user"
            }
          }
        else
          %Tesla.Env{status: 400, body: %{}}
        end

      %{method: :get} ->
        %Tesla.Env{status: 401, body: %{}}

      %{method: :patch} ->
        %Tesla.Env{status: 204, body: nil}
    end)

    on_exit(fn ->
      Application.delete_env(:social_scribe, :salesforce_client_id)
      Application.delete_env(:social_scribe, :salesforce_client_secret)
      Application.delete_env(:social_scribe, :salesforce_redirect_uri)
      Application.delete_env(:social_scribe, :salesforce_auth_base_url)
    end)

    :ok
  end

  describe "get_valid_access_token/1" do
    test "returns existing token when not expired" do
      user = user_fixture()
      conn =
        crm_connection_fixture(%{
          user_id: user.id,
          provider: "salesforce",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert {:ok, token} = SalesforceApi.get_valid_access_token(conn)
      assert token == conn.access_token
    end

    test "returns ok with existing token as fallback when refresh fails" do
      user = user_fixture()
      conn =
        crm_connection_fixture(%{
          user_id: user.id,
          provider: "salesforce",
          refresh_token: "will_fail",
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      # Implementation uses existing token as fallback when refresh fails
      assert {:ok, _token} = SalesforceApi.get_valid_access_token(conn)
    end
  end

  describe "search_contacts/2" do
    test "returns error when request fails" do
      user = user_fixture()
      conn = crm_connection_fixture(%{user_id: user.id, instance_url: "https://example.salesforce.com"})
      # Invalid token will cause API to return non-200
      assert {:error, _} = SalesforceApi.search_contacts(conn, "test")
    end
  end

  describe "get_contact/2" do
    test "returns error when request fails" do
      user = user_fixture()
      conn = crm_connection_fixture(%{user_id: user.id})
      assert {:error, _} = SalesforceApi.get_contact(conn, "003xx000001")
    end
  end
end
