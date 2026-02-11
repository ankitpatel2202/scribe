defmodule SocialScribe.HubspotApiTest do
  use SocialScribe.DataCase, async: false

  alias SocialScribe.HubspotApi

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

  describe "format_contact/1" do
    test "formats a HubSpot contact response correctly" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})
      {:ok, :no_updates} = HubspotApi.apply_updates(credential, "123", [])
    end

    test "apply_updates/3 filters only updates with apply: true" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})
      updates = [
        %{field: "phone", new_value: "555-1234", apply: false},
        %{field: "email", new_value: "test@example.com", apply: false}
      ]
      {:ok, :no_updates} = HubspotApi.apply_updates(credential, "123", updates)
    end

    test "apply_updates/3 applies updates when apply: true" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

      Tesla.Mock.mock(fn %{method: :patch} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "id" => "123",
             "properties" => %{"phone" => "555-1234", "email" => "a@b.com"}
           }
         }}
      end)

      updates = [%{field: "phone", new_value: "555-1234", apply: true}]
      assert {:ok, contact} = HubspotApi.apply_updates(credential, "123", updates)
      assert contact != nil
    end
  end

  describe "search_contacts/2" do
    test "returns contacts on 200" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

      Tesla.Mock.mock(fn %{method: :post, url: url} ->
        assert url =~ "/crm/v3/objects/contacts/search"
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "results" => [
               %{
                 "id" => "1",
                 "properties" => %{
                   "firstname" => "John",
                   "lastname" => "Doe",
                   "email" => "john@example.com"
                 }
               }
             ]
           }
         }}
      end)

      assert {:ok, contacts} = HubspotApi.search_contacts(credential, "john")
      assert length(contacts) == 1
      assert hd(contacts).firstname == "John"
      assert hd(contacts).email == "john@example.com"
    end

    test "returns error on API error status" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, %Tesla.Env{status: 500, body: %{"message" => "Server error"}}}
      end)

      assert {:error, {:api_error, 500, _}} = HubspotApi.search_contacts(credential, "q")
    end

    test "returns error on HTTP failure" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

      Tesla.Mock.mock(fn %{method: :post} -> {:error, :timeout} end)

      assert {:error, {:http_error, :timeout}} = HubspotApi.search_contacts(credential, "q")
    end
  end

  describe "get_contact/2" do
    test "returns formatted contact on 200" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

      Tesla.Mock.mock(fn %{method: :get, url: url} ->
        assert url =~ "/crm/v3/objects/contacts/"
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "id" => "42",
             "properties" => %{
               "firstname" => "Jane",
               "lastname" => "Doe",
               "email" => "jane@example.com",
               "company" => "Acme"
             }
           }
         }}
      end)

      assert {:ok, contact} = HubspotApi.get_contact(credential, "42")
      assert contact.id == "42"
      assert contact.firstname == "Jane"
      assert contact.company == "Acme"
    end

    test "returns :not_found on 404" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

      Tesla.Mock.mock(fn %{method: :get} ->
        {:ok, %Tesla.Env{status: 404, body: %{}}}
      end)

      assert {:error, :not_found} = HubspotApi.get_contact(credential, "missing")
    end
  end

  describe "update_contact/3" do
    test "returns updated contact on 200" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

      Tesla.Mock.mock(fn %{method: :patch} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "id" => "1",
             "properties" => %{"jobtitle" => "Engineer", "email" => "x@y.com"}
           }
         }}
      end)

      assert {:ok, contact} = HubspotApi.update_contact(credential, "1", %{jobtitle: "Engineer"})
      assert contact.jobtitle == "Engineer"
    end

    test "returns :not_found on 404" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

      Tesla.Mock.mock(fn %{method: :patch} ->
        {:ok, %Tesla.Env{status: 404, body: %{}}}
      end)

      assert {:error, :not_found} =
               HubspotApi.update_contact(credential, "missing", %{email: "a@b.com"})
    end
  end
end
