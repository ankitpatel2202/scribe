defmodule SocialScribe.AIContentGeneratorTest do
  use SocialScribe.DataCase, async: false

  import SocialScribe.MeetingsFixtures
  import SocialScribe.MeetingTranscriptExample
  import SocialScribe.AutomationsFixtures
  import SocialScribe.AccountsFixtures

  alias SocialScribe.AIContentGenerator
  alias SocialScribe.Meetings
  alias SocialScribe.Repo

  @gemini_200_body %{
    "candidates" => [
      %{
        "content" => %{
          "parts" => [%{"text" => "Generated response text"}]
        }
      }
    ]
  }

  defp gemini_env(status \\ 200, body \\ @gemini_200_body) do
    %Tesla.Env{status: status, body: body}
  end

  setup do
    Application.put_env(:social_scribe, :gemini_api_key, "test_key")
    on_exit(fn ->
      Application.delete_env(:social_scribe, :gemini_api_key)
    end)
    :ok
  end

  describe "generate_follow_up_email/1" do
    test "returns config_error when API key is missing" do
      Application.delete_env(:social_scribe, :gemini_api_key)

      meeting = meeting_fixture()
      meeting_participant_fixture(%{meeting_id: meeting.id, is_host: true})
      meeting_transcript_fixture(%{meeting_id: meeting.id, content: %{"data" => meeting_transcript_example()}})
      meeting = Meetings.get_meeting_with_details(meeting.id)

      assert {:error, {:config_error, _}} = AIContentGenerator.generate_follow_up_email(meeting)
    end

    test "returns error when Meetings.generate_prompt_for_meeting returns error" do
      meeting = meeting_fixture()
      # No participants -> no_participants
      meeting = Repo.preload(meeting, [:calendar_event, :recall_bot, :meeting_transcript, :meeting_participants])

      assert {:error, :no_participants} = AIContentGenerator.generate_follow_up_email(meeting)
    end

    test "returns ok with generated text when Gemini returns 200" do
      Tesla.Mock.mock(fn %{method: :post, url: url} ->
        assert url =~ "generateContent"
        assert url =~ "key=test_key"
        {:ok, gemini_env(200, @gemini_200_body)}
      end)

      meeting = meeting_fixture()
      meeting_participant_fixture(%{meeting_id: meeting.id, is_host: true})
      meeting_transcript_fixture(%{meeting_id: meeting.id, content: %{"data" => meeting_transcript_example()}})
      meeting = Meetings.get_meeting_with_details(meeting.id)

      assert {:ok, "Generated response text"} = AIContentGenerator.generate_follow_up_email(meeting)
    end
  end

  describe "generate_automation/2" do
    test "returns error when Meetings.generate_prompt_for_meeting returns error" do
      user = user_fixture()
      automation = automation_fixture(%{user_id: user.id})
      meeting = meeting_fixture()
      meeting = Repo.preload(meeting, [:calendar_event, :recall_bot, :meeting_transcript, :meeting_participants])

      assert {:error, :no_participants} = AIContentGenerator.generate_automation(automation, meeting)
    end

    test "returns ok with generated text when Gemini returns 200" do
      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, gemini_env(200, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => "Automation draft"}]}}]})}
      end)

      user = user_fixture()
      automation = automation_fixture(%{user_id: user.id})
      meeting = meeting_fixture()
      meeting_participant_fixture(%{meeting_id: meeting.id, is_host: true})
      meeting_transcript_fixture(%{meeting_id: meeting.id, content: %{"data" => meeting_transcript_example()}})
      meeting = Meetings.get_meeting_with_details(meeting.id)

      assert {:ok, "Automation draft"} = AIContentGenerator.generate_automation(automation, meeting)
    end
  end

  describe "generate_contact_question_answer/3" do
    test "returns config_error when API key is missing" do
      Application.delete_env(:social_scribe, :gemini_api_key)
      assert {:error, {:config_error, _}} = AIContentGenerator.generate_contact_question_answer("What is their email?", [])
    end

    test "returns ok with answer when Gemini returns 200" do
      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, gemini_env(200, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => "Their email is jane@example.com."}]}}]})}
      end)

      assert {:ok, "Their email is jane@example.com."} =
               AIContentGenerator.generate_contact_question_answer("What is their email?", [%{"email" => "jane@example.com"}])
    end

    test "includes meeting_context in prompt when provided in opts" do
      Tesla.Mock.mock(fn %{method: :post, body: body} ->
        # Tesla.Middleware.JSON sends body as string in request
        if is_binary(body), do: assert(body =~ "Context from meeting") and assert(body =~ "meeting details")
        {:ok, gemini_env()}
      end)

      assert {:ok, _} =
               AIContentGenerator.generate_contact_question_answer("Hello?", [], meeting_context: "Context from meeting")
    end

    test "rejects nil entries in contact_data_list" do
      Tesla.Mock.mock(fn %{method: :post, body: body} ->
        # After rejecting nils, only %{"id" => "1"} is sent in the prompt
        if is_binary(body), do: assert(body =~ "id" and body =~ "1")
        {:ok, gemini_env()}
      end)

      assert {:ok, _} = AIContentGenerator.generate_contact_question_answer("Q?", [nil, %{"id" => "1"}, nil])
    end
  end

  describe "generate_hubspot_suggestions/1" do
    test "returns error when Meetings.generate_prompt_for_meeting returns error" do
      meeting = meeting_fixture()
      meeting = Repo.preload(meeting, [:calendar_event, :recall_bot, :meeting_transcript, :meeting_participants])

      assert {:error, :no_participants} = AIContentGenerator.generate_hubspot_suggestions(meeting)
    end

    test "returns parsed suggestions when Gemini returns valid JSON array" do
      json = Jason.encode!([
        %{"field" => "phone", "value" => "555-1234", "context" => "mentioned", "timestamp" => "01:00"},
        %{"field" => "email", "value" => "a@b.com", "context" => "said", "timestamp" => "02:00"}
      ])

      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, gemini_env(200, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => json}]}}]})}
      end)

      meeting = meeting_fixture()
      meeting_participant_fixture(%{meeting_id: meeting.id, is_host: true})
      meeting_transcript_fixture(%{meeting_id: meeting.id, content: %{"data" => meeting_transcript_example()}})
      meeting = Meetings.get_meeting_with_details(meeting.id)

      assert {:ok, suggestions} = AIContentGenerator.generate_hubspot_suggestions(meeting)
      assert length(suggestions) == 2
      assert Enum.any?(suggestions, fn s -> s.field == "phone" and s.value == "555-1234" end)
      assert Enum.any?(suggestions, fn s -> s.field == "email" and s.value == "a@b.com" end)
    end

    test "strips markdown code blocks from response before parsing" do
      json = Jason.encode!([%{"field" => "phone", "value" => "555", "context" => "x", "timestamp" => "0:00"}])
      wrapped = "```json\n#{json}\n```"

      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, gemini_env(200, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => wrapped}]}}]})}
      end)

      meeting = meeting_fixture()
      meeting_participant_fixture(%{meeting_id: meeting.id, is_host: true})
      meeting_transcript_fixture(%{meeting_id: meeting.id, content: %{"data" => meeting_transcript_example()}})
      meeting = Meetings.get_meeting_with_details(meeting.id)

      assert {:ok, [%{field: "phone", value: "555"}]} = AIContentGenerator.generate_hubspot_suggestions(meeting)
    end

    test "returns empty list when response is not a JSON array" do
      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, gemini_env(200, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => "{\"foo\": 1}"}]}}]})}
      end)

      meeting = meeting_fixture()
      meeting_participant_fixture(%{meeting_id: meeting.id, is_host: true})
      meeting_transcript_fixture(%{meeting_id: meeting.id, content: %{"data" => meeting_transcript_example()}})
      meeting = Meetings.get_meeting_with_details(meeting.id)

      assert {:ok, []} = AIContentGenerator.generate_hubspot_suggestions(meeting)
    end

    test "returns empty list when JSON is invalid" do
      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, gemini_env(200, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => "not json at all"}]}}]})}
      end)

      meeting = meeting_fixture()
      meeting_participant_fixture(%{meeting_id: meeting.id, is_host: true})
      meeting_transcript_fixture(%{meeting_id: meeting.id, content: %{"data" => meeting_transcript_example()}})
      meeting = Meetings.get_meeting_with_details(meeting.id)

      assert {:ok, []} = AIContentGenerator.generate_hubspot_suggestions(meeting)
    end

    test "filters out suggestions with nil field or value" do
      json = Jason.encode!([
        %{"field" => "phone", "value" => "555", "context" => "x", "timestamp" => "0:00"},
        %{"field" => nil, "value" => "y", "context" => "x", "timestamp" => "0:00"},
        %{"field" => "email", "value" => nil, "context" => "x", "timestamp" => "0:00"}
      ])

      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, gemini_env(200, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => json}]}}]})}
      end)

      meeting = meeting_fixture()
      meeting_participant_fixture(%{meeting_id: meeting.id, is_host: true})
      meeting_transcript_fixture(%{meeting_id: meeting.id, content: %{"data" => meeting_transcript_example()}})
      meeting = Meetings.get_meeting_with_details(meeting.id)

      assert {:ok, [%{field: "phone"}]} = AIContentGenerator.generate_hubspot_suggestions(meeting)
    end
  end

  describe "generate_salesforce_contact_updates/2" do
    test "returns :no_transcript when Meetings.generate_prompt_for_meeting returns error" do
      meeting = meeting_fixture()
      meeting = Repo.preload(meeting, [:calendar_event, :recall_bot, :meeting_transcript, :meeting_participants])
      contact = %{"FirstName" => "Jane", "LastName" => "Doe", "Email" => "j@x.com"}

      assert {:error, :no_transcript} = AIContentGenerator.generate_salesforce_contact_updates(meeting, contact)
    end

    test "returns parsed updates when Gemini returns valid JSON array" do
      json = Jason.encode!([
        %{"field" => "Phone", "current_value" => nil, "suggested_value" => "555-9999", "reason" => "From transcript"},
        %{"field" => "Title", "current_value" => "Engineer", "suggested_value" => "Senior Engineer", "reason" => "Promotion mentioned"}
      ])

      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, gemini_env(200, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => json}]}}]})}
      end)

      meeting = meeting_fixture()
      meeting_participant_fixture(%{meeting_id: meeting.id, is_host: true})
      meeting_transcript_fixture(%{meeting_id: meeting.id, content: %{"data" => meeting_transcript_example()}})
      meeting = Meetings.get_meeting_with_details(meeting.id)
      contact = %{"FirstName" => "Jane", "LastName" => "Doe"}

      assert {:ok, updates} = AIContentGenerator.generate_salesforce_contact_updates(meeting, contact)
      assert length(updates) == 2
      assert Enum.any?(updates, fn u -> u["field"] == "Phone" and u["suggested_value"] == "555-9999" and u["reason"] == "From transcript" end)
      assert Enum.any?(updates, fn u -> u["field"] == "Title" and u["current_value"] == "Engineer" and u["suggested_value"] == "Senior Engineer" end)
    end

    test "uses default reason when reason missing" do
      json = Jason.encode!([%{"field" => "Phone", "suggested_value" => "555"}])

      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, gemini_env(200, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => json}]}}]})}
      end)

      meeting = meeting_fixture()
      meeting_participant_fixture(%{meeting_id: meeting.id, is_host: true})
      meeting_transcript_fixture(%{meeting_id: meeting.id, content: %{"data" => meeting_transcript_example()}})
      meeting = Meetings.get_meeting_with_details(meeting.id)

      assert {:ok, [%{"reason" => "From meeting"}]} = AIContentGenerator.generate_salesforce_contact_updates(meeting, %{})
    end

    test "returns parsing_error when response is not valid JSON array" do
      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, gemini_env(200, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => "not json"}]}}]})}
      end)

      meeting = meeting_fixture()
      meeting_participant_fixture(%{meeting_id: meeting.id, is_host: true})
      meeting_transcript_fixture(%{meeting_id: meeting.id, content: %{"data" => meeting_transcript_example()}})
      meeting = Meetings.get_meeting_with_details(meeting.id)

      assert {:error, {:parsing_error, _, _}} = AIContentGenerator.generate_salesforce_contact_updates(meeting, %{})
    end

    test "strips markdown code fences before parsing" do
      json = Jason.encode!([%{"field" => "Phone", "suggested_value" => "555", "reason" => "Ok"}])
      wrapped = "```json\n#{json}\n```"

      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, gemini_env(200, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => wrapped}]}}]})}
      end)

      meeting = meeting_fixture()
      meeting_participant_fixture(%{meeting_id: meeting.id, is_host: true})
      meeting_transcript_fixture(%{meeting_id: meeting.id, content: %{"data" => meeting_transcript_example()}})
      meeting = Meetings.get_meeting_with_details(meeting.id)

      assert {:ok, [%{"field" => "Phone"}]} = AIContentGenerator.generate_salesforce_contact_updates(meeting, %{})
    end
  end

  describe "call_gemini (via public functions)" do
    test "returns parsing_error when Gemini 200 body has no text content" do
      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, %Tesla.Env{status: 200, body: %{"candidates" => [%{"content" => %{"parts" => []}}]}}}
      end)

      assert {:error, {:parsing_error, "No text content found in Gemini response", _}} =
               AIContentGenerator.generate_contact_question_answer("Q?", [])
    end

    test "returns api_error on non-200 non-429 status" do
      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, %Tesla.Env{status: 500, body: %{"error" => "Internal"}}}
      end)

      assert {:error, {:api_error, 500, _}} = AIContentGenerator.generate_contact_question_answer("Q?", [])
    end

    test "returns http_error on Tesla failure" do
      Tesla.Mock.mock(fn %{method: :post} ->
        {:error, :timeout}
      end)

      assert {:error, {:http_error, :timeout}} = AIContentGenerator.generate_contact_question_answer("Q?", [])
    end

    test "retries on 429 and succeeds when second request returns 200" do
      call_count = :counters.new(1, [])
      Tesla.Mock.mock(fn %{method: :post} ->
        c = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)
        if c == 0 do
          # First call: 429 with 0s retry so we don't sleep long
          {:ok,
           %Tesla.Env{
             status: 429,
             body: %{
               "error" => %{
                 "details" => [
                   %{"@type" => "type.googleapis.com/google.rpc.RetryInfo", "retryDelay" => "0s"}
                 ]
               }
             }
           }}
        else
          {:ok, gemini_env(200, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => "After retry"}]}}]})}
        end
      end)

      assert {:ok, "After retry"} = AIContentGenerator.generate_contact_question_answer("Q?", [])
    end

    test "retries on 429 with message 'retry in Xs' and uses parsed seconds" do
      call_count = :counters.new(1, [])
      Tesla.Mock.mock(fn %{method: :post} ->
        c = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)
        if c == 0 do
          {:ok,
           %Tesla.Env{
             status: 429,
             body: %{"error" => %{"message" => "Resource exhausted. Please retry in 0.5s"}}
           }}
        else
          {:ok, gemini_env(200, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => "OK"}]}}]})}
        end
      end)

      assert {:ok, "OK"} = AIContentGenerator.generate_contact_question_answer("Q?", [])
    end
  end
end
