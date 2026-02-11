defmodule SocialScribe.HubspotSuggestionsTest do
  use SocialScribe.DataCase, async: false

  alias SocialScribe.HubspotSuggestions

  import SocialScribe.AccountsFixtures
  import Mox

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

  setup :verify_on_exit!

  describe "generate_suggestions_from_meeting/1" do
    test "returns suggestions when AI returns success" do
      meeting = %{id: 1, title: "Test"}
      ai_suggestions = [
        %{field: "phone", value: "555-1234", context: "From transcript"},
        %{field: "company", value: "Acme", context: "Mentioned"}
      ]

      SocialScribe.AIContentGeneratorMock
      |> stub(:generate_hubspot_suggestions, fn ^meeting ->
        {:ok, ai_suggestions}
      end)

      assert {:ok, suggestions} = HubspotSuggestions.generate_suggestions_from_meeting(meeting)
      assert length(suggestions) == 2
      assert Enum.any?(suggestions, fn s -> s.field == "phone" and s.new_value == "555-1234" end)
    end

    test "returns error when AI fails" do
      SocialScribe.AIContentGeneratorMock
      |> stub(:generate_hubspot_suggestions, fn _ -> {:error, :no_transcript} end)

      assert {:error, :no_transcript} =
               HubspotSuggestions.generate_suggestions_from_meeting(%{id: 1})
    end
  end

  describe "generate_suggestions/3" do
    test "returns contact and suggestions when both API and AI succeed" do
      user = user_fixture()
      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })
      meeting = %{id: 1, title: "Call"}
      ai_suggestions = [%{field: "company", value: "New Co", context: "Updated"}]

      Tesla.Mock.mock(fn %{method: :get} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "id" => "c1",
             "properties" => %{
               "firstname" => "John",
               "lastname" => "Doe",
               "email" => "j@example.com",
               "company" => "Old Co"
             }
           }
         }}
      end)

      SocialScribe.AIContentGeneratorMock
      |> stub(:generate_hubspot_suggestions, fn ^meeting -> {:ok, ai_suggestions} end)

      assert {:ok, %{contact: contact, suggestions: suggestions}} =
               HubspotSuggestions.generate_suggestions(credential, "c1", meeting)

      assert contact.company == "Old Co"
      assert length(suggestions) == 1
      assert hd(suggestions).field == "company"
      assert hd(suggestions).new_value == "New Co"
      assert hd(suggestions).current_value == "Old Co"
    end

    test "returns error when get_contact fails" do
      user = user_fixture()
      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      Tesla.Mock.mock(fn %{method: :get} ->
        {:ok, %Tesla.Env{status: 404, body: %{}}}
      end)

      assert {:error, :not_found} =
               HubspotSuggestions.generate_suggestions(credential, "bad", %{})
    end

    test "returns error when generate_hubspot_suggestions fails" do
      user = user_fixture()
      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      Tesla.Mock.mock(fn %{method: :get} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "id" => "c1",
             "properties" => %{"email" => "j@example.com", "company" => nil}
           }
         }}
      end)

      SocialScribe.AIContentGeneratorMock
      |> stub(:generate_hubspot_suggestions, fn _ -> {:error, :rate_limited} end)

      assert {:error, :rate_limited} =
               HubspotSuggestions.generate_suggestions(credential, "c1", %{id: 1})
    end
  end

  describe "merge_with_contact/2" do
    test "merges suggestions with contact data and filters unchanged values" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "Mentioned in call",
          apply: false,
          has_change: true
        },
        %{
          field: "company",
          label: "Company",
          current_value: nil,
          new_value: "Acme Corp",
          context: "Works at Acme",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "123",
        phone: nil,
        company: "Acme Corp",
        email: "test@example.com"
      }

      result = HubspotSuggestions.merge_with_contact(suggestions, contact)

      # Only phone should remain since company already matches
      assert length(result) == 1
      assert hd(result).field == "phone"
      assert hd(result).new_value == "555-1234"
    end

    test "returns empty list when all suggestions match current values" do
      suggestions = [
        %{
          field: "email",
          label: "Email",
          current_value: nil,
          new_value: "test@example.com",
          context: "Email mentioned",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "123",
        email: "test@example.com"
      }

      result = HubspotSuggestions.merge_with_contact(suggestions, contact)

      assert result == []
    end

    test "handles empty suggestions list" do
      contact = %{id: "123", email: "test@example.com"}

      result = HubspotSuggestions.merge_with_contact([], contact)

      assert result == []
    end
  end

  describe "field_labels" do
    test "common fields have human-readable labels" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "123", phone: nil}

      result = HubspotSuggestions.merge_with_contact(suggestions, contact)

      assert hd(result).label == "Phone"
    end
  end
end
