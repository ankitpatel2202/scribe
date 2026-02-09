defmodule SocialScribe.Workers.HubspotTokenRefresherWorkerTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.Workers.HubspotTokenRefresher

  import SocialScribe.AccountsFixtures

  describe "perform/1" do
    test "returns :ok when no HubSpot credentials are expiring" do
      # No hubspot credentials in DB
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
  end
end
