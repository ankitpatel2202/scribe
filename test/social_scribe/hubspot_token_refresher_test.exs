defmodule SocialScribe.HubspotTokenRefresherTest do
  use SocialScribe.DataCase, async: false

  alias SocialScribe.HubspotTokenRefresher

  import SocialScribe.AccountsFixtures

  setup do
    Application.put_env(:ueberauth, Ueberauth.Strategy.Hubspot.OAuth, [
      client_id: "test_id",
      client_secret: "test_secret"
    ])
    on_exit(fn ->
      Application.delete_env(:ueberauth, Ueberauth.Strategy.Hubspot.OAuth)
    end)
    :ok
  end

  describe "ensure_valid_token/1" do
    test "returns credential unchanged when token is not expired" do
      user = user_fixture()

      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      {:ok, result} = HubspotTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "returns credential unchanged when token expires in more than 5 minutes" do
      user = user_fixture()

      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        })

      {:ok, result} = HubspotTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "refreshes when token is expired and returns updated credential" do
      user = user_fixture()

      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), -100, :second),
          token: "old_token",
          refresh_token: "old_refresh"
        })

      Tesla.Mock.mock(fn %{method: :post, url: url} ->
        assert url =~ "oauth/v1/token"
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "access_token" => "new_access_token",
             "refresh_token" => "new_refresh_token",
             "expires_in" => 3600
           }
         }}
      end)

      {:ok, result} = HubspotTokenRefresher.ensure_valid_token(credential)
      assert result.token == "new_access_token"
      assert result.refresh_token == "new_refresh_token"
    end
  end

  describe "refresh_token/1" do
    test "returns new tokens on 200" do
      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "access_token" => "at",
             "refresh_token" => "rt",
             "expires_in" => 1800
           }
         }}
      end)

      assert {:ok, body} = HubspotTokenRefresher.refresh_token("my_refresh")
      assert body["access_token"] == "at"
      assert body["refresh_token"] == "rt"
    end

    test "returns error on non-200 status" do
      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, %Tesla.Env{status: 400, body: %{"message" => "Invalid refresh token"}}}
      end)

      assert {:error, {400, _}} = HubspotTokenRefresher.refresh_token("bad")
    end

    test "returns error on HTTP failure" do
      Tesla.Mock.mock(fn %{method: :post} -> {:error, :timeout} end)
      assert {:error, :timeout} = HubspotTokenRefresher.refresh_token("any")
    end
  end

  describe "refresh_credential/1" do
    test "updates credential in database on successful refresh" do
      user = user_fixture()

      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          token: "old_token",
          refresh_token: "old_refresh"
        })

      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "access_token" => "new_access_token",
             "refresh_token" => "new_refresh_token",
             "expires_in" => 3600
           }
         }}
      end)

      {:ok, updated} = HubspotTokenRefresher.refresh_credential(credential)
      assert updated.token == "new_access_token"
      assert updated.refresh_token == "new_refresh_token"
      assert updated.id == credential.id
    end

    test "returns error when refresh API fails" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id, refresh_token: "bad"})

      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, %Tesla.Env{status: 400, body: %{}}}
      end)

      assert {:error, {400, _}} = HubspotTokenRefresher.refresh_credential(credential)
    end
  end
end
