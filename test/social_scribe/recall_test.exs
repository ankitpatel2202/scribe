defmodule SocialScribe.RecallTest do
  use ExUnit.Case, async: false

  alias SocialScribe.Recall

  @join_at ~U[2025-06-01 14:00:00Z]

  setup do
    Application.put_env(:social_scribe, :recall_api_key, "test_recall_key")
    Application.put_env(:social_scribe, :recall_region, "us")

    on_exit(fn ->
      Application.delete_env(:social_scribe, :recall_api_key)
      Application.delete_env(:social_scribe, :recall_region)
      Application.delete_env(:social_scribe, :recall_transcript_webhook_url)
    end)

    :ok
  end

  describe "create_bot/2" do
    test "returns ok with env when API returns 200" do
      Tesla.Mock.mock(fn %{method: :post, url: url} ->
        assert url =~ "/bot"
        {:ok, %Tesla.Env{status: 200, body: %{id: "bot-123", status: "pending"}}}
      end)

      assert {:ok, %Tesla.Env{status: 200, body: %{id: "bot-123"}}} =
               Recall.create_bot("https://meet.google.com/abc-def", @join_at)
    end

    test "request body includes meeting_url, bot_name, join_at and recording_config when no webhook" do
      Tesla.Mock.mock(fn %{method: :post, body: body} ->
        body_map = if is_binary(body), do: Jason.decode!(body), else: body
        assert body_map["meeting_url"] == "https://meet.google.com/xyz"
        assert body_map["bot_name"] == "Social Scribe Bot"
        assert body_map["join_at"] != nil
        assert body_map["recording_config"]["transcript"]["provider"]["meeting_captions"] == %{}
        refute Map.has_key?(body_map["recording_config"] || %{}, "realtime_endpoints")
        {:ok, %Tesla.Env{status: 200, body: %{}}}
      end)

      assert {:ok, _} = Recall.create_bot("https://meet.google.com/xyz", @join_at)
    end

    test "request body includes realtime_endpoints when recall_transcript_webhook_url is set" do
      Application.put_env(:social_scribe, :recall_transcript_webhook_url, "https://my.app/webhook")

      Tesla.Mock.mock(fn %{method: :post, body: body} ->
        body_map = if is_binary(body), do: Jason.decode!(body), else: body
        assert body_map["recording_config"]["realtime_endpoints"] == [
                 %{
                   "type" => "webhook",
                   "url" => "https://my.app/webhook",
                   "events" => ["transcript.data", "transcript.partial_data"]
                 }
               ]
        assert body_map["recording_config"]["transcript"]["provider"]["recallai_streaming"] == %{}
        {:ok, %Tesla.Env{status: 200, body: %{}}}
      end)

      assert {:ok, _} = Recall.create_bot("https://meet.google.com/abc", @join_at)
    end

    test "returns error when API returns non-success" do
      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, %Tesla.Env{status: 400, body: %{"error" => "Invalid meeting URL"}}}
      end)

      assert {:ok, %Tesla.Env{status: 400}} = Recall.create_bot("invalid", @join_at)
    end

    test "returns error when Tesla fails" do
      Tesla.Mock.mock(fn %{method: :post} ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Recall.create_bot("https://meet.google.com/x", @join_at)
    end
  end

  describe "update_bot/3" do
    test "returns ok when API returns 200" do
      Tesla.Mock.mock(fn %{method: :patch, url: url, body: body} ->
        assert String.contains?(url, "/bot/bot-456")
        body_map = if is_binary(body), do: Jason.decode!(body), else: body
        assert body_map["meeting_url"] == "https://zoom.us/j/789"
        assert body_map["join_at"] != nil
        {:ok, %Tesla.Env{status: 200, body: %{id: "bot-456"}}}
      end)

      assert {:ok, %Tesla.Env{status: 200}} =
               Recall.update_bot("bot-456", "https://zoom.us/j/789", @join_at)
    end

    test "returns error when Tesla fails" do
      Tesla.Mock.mock(fn %{method: :patch} ->
        {:error, :nxdomain}
      end)

      assert {:error, :nxdomain} = Recall.update_bot("bot-1", "https://meet.google.com/x", @join_at)
    end
  end

  describe "delete_bot/1" do
    test "returns ok when API returns 200" do
      Tesla.Mock.mock(fn %{method: :delete, url: url} ->
        assert url =~ "/bot/bot-789"
        {:ok, %Tesla.Env{status: 200, body: %{}}}
      end)

      assert {:ok, %Tesla.Env{status: 200}} = Recall.delete_bot("bot-789")
    end

    test "returns error when Tesla fails" do
      Tesla.Mock.mock(fn %{method: :delete} ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Recall.delete_bot("bot-1")
    end
  end

  describe "get_bot/1" do
    test "returns ok with bot body when API returns 200" do
      Tesla.Mock.mock(fn %{method: :get, url: url} ->
        assert url =~ "/bot/bot-abc"
        {:ok, %Tesla.Env{status: 200, body: %{id: "bot-abc", status: "done"}}}
      end)

      assert {:ok, %Tesla.Env{status: 200, body: %{id: "bot-abc", status: "done"}}} =
               Recall.get_bot("bot-abc")
    end

    test "returns error when Tesla fails" do
      Tesla.Mock.mock(fn %{method: :get} ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Recall.get_bot("bot-1")
    end
  end

  describe "get_bot_transcript/1" do
    test "returns transcript via recording download_url when available" do
      transcript_list = [%{"speaker" => "Alice", "text" => "Hello"}, %{"speaker" => "Bob", "text" => "Hi"}]

      Tesla.Mock.mock(fn %{method: :get, url: url} ->
        cond do
          String.contains?(url, "/bot/") and not String.contains?(url, "/transcript") ->
            {:ok, %Tesla.Env{status: 200, body: %{recordings: [%{id: "rec-1"}]}}}

          String.contains?(url, "/recording/") ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 media_shortcuts: %{
                   transcript: %{data: %{download_url: "https://storage.recall.ai/transcript.json"}}
                 }
               }
             }}

          url == "https://storage.recall.ai/transcript.json" ->
            {:ok, %Tesla.Env{status: 200, body: transcript_list}}

          true ->
            raise "Unexpected GET: #{url}"
        end
      end)

      assert {:ok, %Tesla.Env{status: 200, body: ^transcript_list}} =
               Recall.get_bot_transcript("bot-1")
    end

    test "falls back to GET /bot/:id/transcript/ when no recordings" do
      transcript_list = [%{"text" => "Fallback transcript"}]

      Tesla.Mock.mock(fn %{method: :get, url: url} ->
        cond do
          String.contains?(url, "/bot/") and not String.contains?(url, "/transcript") ->
            {:ok, %Tesla.Env{status: 200, body: %{recordings: []}}}

          String.contains?(url, "/transcript/") ->
            {:ok, %Tesla.Env{status: 200, body: transcript_list}}

          true ->
            raise "Unexpected GET: #{url}"
        end
      end)

      assert {:ok, %Tesla.Env{status: 200, body: ^transcript_list}} =
               Recall.get_bot_transcript("bot-no-rec")
    end

    test "falls back to GET /bot/:id/transcript/ when recording has no transcript download_url" do
      transcript_list = [%{"text" => "From fallback"}]

      Tesla.Mock.mock(fn %{method: :get, url: url} ->
        cond do
          String.contains?(url, "/bot/") and not String.contains?(url, "/transcript") ->
            {:ok, %Tesla.Env{status: 200, body: %{recordings: [%{id: "rec-2"}]}}}

          String.contains?(url, "/recording/") ->
            {:ok, %Tesla.Env{status: 200, body: %{media_shortcuts: %{}}}}

          String.contains?(url, "/transcript/") ->
            {:ok, %Tesla.Env{status: 200, body: transcript_list}}

          true ->
            raise "Unexpected GET: #{url}"
        end
      end)

      assert {:ok, %Tesla.Env{status: 200, body: ^transcript_list}} =
               Recall.get_bot_transcript("bot-no-url")
    end

    test "fallback normalizes %{\"transcript\" => list} body" do
      inner = [%{"speaker" => "S1", "text" => "Hi"}]

      Tesla.Mock.mock(fn %{method: :get, url: url} ->
        cond do
          String.contains?(url, "/bot/") and not String.contains?(url, "/transcript") ->
            {:ok, %Tesla.Env{status: 200, body: %{recordings: []}}}

          String.contains?(url, "/transcript/") ->
            {:ok, %Tesla.Env{status: 200, body: %{"transcript" => inner}}}

          true ->
            raise "Unexpected GET: #{url}"
        end
      end)

      assert {:ok, %Tesla.Env{body: ^inner}} = Recall.get_bot_transcript("bot-norm")
    end

    test "fallback normalizes %{\"data\" => list} body" do
      inner = [%{"text" => "Data key"}]

      Tesla.Mock.mock(fn %{method: :get, url: url} ->
        cond do
          String.contains?(url, "/bot/") and not String.contains?(url, "/transcript") ->
            {:ok, %Tesla.Env{status: 200, body: %{recordings: []}}}

          String.contains?(url, "/transcript/") ->
            {:ok, %Tesla.Env{status: 200, body: %{"data" => inner}}}

          true ->
            raise "Unexpected GET: #{url}"
        end
      end)

      assert {:ok, %Tesla.Env{body: ^inner}} = Recall.get_bot_transcript("bot-data")
    end

    test "fallback returns no_transcript_url on 404" do
      Tesla.Mock.mock(fn %{method: :get, url: url} ->
        cond do
          String.contains?(url, "/bot/") and not String.contains?(url, "/transcript") ->
            {:ok, %Tesla.Env{status: 200, body: %{recordings: []}}}

          String.contains?(url, "/transcript/") ->
            {:ok, %Tesla.Env{status: 404, body: %{}}}

          true ->
            raise "Unexpected GET: #{url}"
        end
      end)

      assert {:error, :no_transcript_url} = Recall.get_bot_transcript("bot-404")
    end

    test "propagates get_bot error" do
      Tesla.Mock.mock(fn %{method: :get, url: url} ->
        if String.contains?(url, "/bot/") and not String.contains?(url, "/transcript") do
          {:error, :timeout}
        else
          raise "Unexpected GET: #{url}"
        end
      end)

      assert {:error, :timeout} = Recall.get_bot_transcript("bot-err")
    end
  end

  describe "get_bot_participants/1" do
    test "returns participants via media_shortcuts participant_events url" do
      participants = [%{"id" => "p1", "name" => "Alice"}, %{"id" => "p2", "name" => "Bob"}]

      Tesla.Mock.mock(fn %{method: :get, url: url} ->
        cond do
          String.contains?(url, "/bot/") and not String.contains?(url, "/recording") ->
            {:ok, %Tesla.Env{status: 200, body: %{recordings: [%{id: "rec-p"}]}}}

          String.contains?(url, "/recording/") ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 media_shortcuts: %{
                   participant_events: %{
                     data: %{participants_download_url: "https://storage.recall.ai/participants.json"}
                   }
                 }
               }
             }}

          url == "https://storage.recall.ai/participants.json" ->
            {:ok, %Tesla.Env{status: 200, body: participants}}

          true ->
            raise "Unexpected GET: #{url}"
        end
      end)

      assert {:ok, %Tesla.Env{status: 200, body: ^participants}} =
               Recall.get_bot_participants("bot-p")
    end

    test "returns participants via fallback participant_events.data.participants_download_url" do
      participants = [%{"name" => "Solo"}]

      Tesla.Mock.mock(fn %{method: :get, url: url} ->
        cond do
          String.contains?(url, "/bot/") and not String.contains?(url, "/recording") ->
            {:ok, %Tesla.Env{status: 200, body: %{recordings: [%{id: "rec-old"}]}}}

          String.contains?(url, "/recording/") ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 participant_events: %{data: %{participants_download_url: "https://storage.recall.ai/old-participants.json"}}
               }
             }}

          url == "https://storage.recall.ai/old-participants.json" ->
            {:ok, %Tesla.Env{status: 200, body: participants}}

          true ->
            raise "Unexpected GET: #{url}"
        end
      end)

      assert {:ok, %Tesla.Env{status: 200, body: ^participants}} =
               Recall.get_bot_participants("bot-old")
    end

    test "returns no_recordings when bot has no recordings" do
      Tesla.Mock.mock(fn %{method: :get, url: url} ->
        if String.contains?(url, "/bot/") do
          {:ok, %Tesla.Env{status: 200, body: %{recordings: []}}}
        else
          raise "Unexpected GET: #{url}"
        end
      end)

      assert {:error, :no_recordings} = Recall.get_bot_participants("bot-empty")
    end

    test "returns no_participants_url when recording has no participants url" do
      Tesla.Mock.mock(fn %{method: :get, url: url} ->
        cond do
          String.contains?(url, "/bot/") and not String.contains?(url, "/recording") ->
            {:ok, %Tesla.Env{status: 200, body: %{recordings: [%{id: "rec-nourl"}]}}}

          String.contains?(url, "/recording/") ->
            {:ok, %Tesla.Env{status: 200, body: %{}}}

          true ->
            raise "Unexpected GET: #{url}"
        end
      end)

      assert {:error, :no_participants_url} = Recall.get_bot_participants("bot-nourl")
    end

    test "propagates get_bot error" do
      Tesla.Mock.mock(fn %{method: :get, url: url} ->
        if String.contains?(url, "/bot/") do
          {:error, :nxdomain}
        else
          raise "Unexpected GET: #{url}"
        end
      end)

      assert {:error, :nxdomain} = Recall.get_bot_participants("bot-err")
    end
  end

  describe "config" do
    test "raises when recall_api_key is missing" do
      Application.delete_env(:social_scribe, :recall_api_key)

      assert_raise ArgumentError, fn ->
        Recall.get_bot("bot-1")
      end
    end

    test "raises when recall_region is missing" do
      Application.delete_env(:social_scribe, :recall_region)

      assert_raise ArgumentError, fn ->
        Recall.get_bot("bot-1")
      end
    end
  end
end
