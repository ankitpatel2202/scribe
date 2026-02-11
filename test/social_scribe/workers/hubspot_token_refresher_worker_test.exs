defmodule SocialScribe.Workers.HubspotTokenRefresherWorkerTest do
  use SocialScribe.DataCase, async: false

  alias SocialScribe.Workers.HubspotTokenRefresher

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

  describe "perform/1" do
    test "returns :ok when no HubSpot credentials are expiring" do
      assert :ok = HubspotTokenRefresher.perform(%Oban.Job{args: %{}})
    end

    test "returns :ok when HubSpot credentials exist but are not expiring soon" do
      user = user_fixture()
      hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

      assert :ok = HubspotTokenRefresher.perform(%Oban.Job{args: %{}})
    end

    test "refreshes credentials that are expiring within 10 minutes" do
      user = user_fixture()
      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 5, :minute),
          refresh_token: "refresh_me"
        })

      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "access_token" => "new_at",
             "refresh_token" => "new_rt",
             "expires_in" => 3600
           }
         }}
      end)

      assert :ok = HubspotTokenRefresher.perform(%Oban.Job{args: %{}})

      updated = SocialScribe.Accounts.get_user_credential!(credential.id)
      assert updated.token == "new_at"
      assert updated.refresh_token == "new_rt"
    end
  end
end
