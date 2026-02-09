defmodule SocialScribe.AIContentGenerator do
  @moduledoc "Generates content using Google Gemini."

  @behaviour SocialScribe.AIContentGeneratorApi

  alias SocialScribe.Meetings
  alias SocialScribe.Automations

  @gemini_model "gemini-2.0-flash-lite"
  @gemini_api_base_url "https://generativelanguage.googleapis.com/v1beta/models"

  @impl SocialScribe.AIContentGeneratorApi
  def generate_follow_up_email(meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        prompt = """
        Based on the following meeting transcript, please draft a concise and professional follow-up email.
        The email should summarize the key discussion points and clearly list any action items assigned, including who is responsible if mentioned.
        Keep the tone friendly and action-oriented.

        #{meeting_prompt}
        """

        call_gemini(prompt)
    end
  end

  @impl SocialScribe.AIContentGeneratorApi
  def generate_automation(automation, meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        prompt = """
        #{Automations.generate_prompt_for_automation(automation)}

        #{meeting_prompt}
        """

        call_gemini(prompt)
    end
  end

  @impl SocialScribe.AIContentGeneratorApi
  def generate_hubspot_suggestions(meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        prompt = """
        You are an AI assistant that extracts contact information updates from meeting transcripts.

        Analyze the following meeting transcript and extract any information that could be used to update a CRM contact record.

        Look for mentions of:
        - Phone numbers (phone, mobilephone)
        - Email addresses (email)
        - Company name (company)
        - Job title/role (jobtitle)
        - Physical address details (address, city, state, zip, country)
        - Website URLs (website)
        - LinkedIn profile (linkedin_url)
        - Twitter handle (twitter_handle)

        IMPORTANT: Only extract information that is EXPLICITLY mentioned in the transcript. Do not infer or guess.

        The transcript includes timestamps in [MM:SS] format at the start of each line.

        Return your response as a JSON array of objects. Each object should have:
        - "field": the CRM field name (use exactly: firstname, lastname, email, phone, mobilephone, company, jobtitle, address, city, state, zip, country, website, linkedin_url, twitter_handle)
        - "value": the extracted value
        - "context": a brief quote of where this was mentioned
        - "timestamp": the timestamp in MM:SS format where this was mentioned

        If no contact information updates are found, return an empty array: []

        Example response format:
        [
          {"field": "phone", "value": "555-123-4567", "context": "John mentioned 'you can reach me at 555-123-4567'", "timestamp": "01:23"},
          {"field": "company", "value": "Acme Corp", "context": "Sarah said she just joined Acme Corp", "timestamp": "05:47"}
        ]

        ONLY return valid JSON, no other text.

        Meeting transcript:
        #{meeting_prompt}
        """

        case call_gemini(prompt) do
          {:ok, response} ->
            parse_hubspot_suggestions(response)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp parse_hubspot_suggestions(response) do
    # Clean up the response - remove markdown code blocks if present
    cleaned =
      response
      |> String.trim()
      |> String.replace(~r/^```json\n?/, "")
      |> String.replace(~r/\n?```$/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, suggestions} when is_list(suggestions) ->
        formatted =
          suggestions
          |> Enum.filter(&is_map/1)
          |> Enum.map(fn s ->
            %{
              field: s["field"],
              value: s["value"],
              context: s["context"],
              timestamp: s["timestamp"]
            }
          end)
          |> Enum.filter(fn s -> s.field != nil and s.value != nil end)

        {:ok, formatted}

      {:ok, _} ->
        {:ok, []}

      {:error, _} ->
        # If JSON parsing fails, return empty suggestions
        {:ok, []}
    end
  end

  @impl SocialScribe.AIContentGeneratorApi
  def generate_contact_question_answer(question, contact_data_list) when is_binary(question) do
    contact_json =
      contact_data_list
      |> Enum.reject(&is_nil/1)
      |> Jason.encode!(pretty: false)

    prompt = """
    You are a helpful assistant that answers questions about CRM contacts.
    The user asked a question about their contact(s). Use ONLY the following contact data to answer.
    Be concise and accurate. If the contact data does not contain enough information to answer, say so.

    Contact data (JSON):
    #{contact_json}

    User question: #{question}

    Answer (plain text, no markdown):
    """

    call_gemini(prompt)
  end

  @impl SocialScribe.AIContentGeneratorApi
  def generate_salesforce_contact_updates(meeting, contact_record) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, _reason} ->
        {:error, :no_transcript}

      {:ok, meeting_prompt} ->
        contact_json = Jason.encode!(contact_record, pretty: false)

        prompt = """
        You are analyzing a meeting transcript to suggest updates to a Salesforce Contact record.
        Given the meeting transcript and the CURRENT contact record (JSON) below, suggest only updates that are explicitly or clearly implied in the transcript.
        Examples: if someone says "my phone number is 8885550000" suggest updating Phone; if they say "you can reach me at new@email.com" suggest Email.

        Return ONLY a valid JSON array of objects. Each object must have exactly these keys:
        - "field": Salesforce Contact API field name (e.g. Phone, Email, Title, MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry, FirstName, LastName, Department, Description)
        - "current_value": the current value in the contact record (string or null)
        - "suggested_value": the new value to set (string)
        - "reason": one short sentence explaining why (from the transcript)

        Only include fields that should be updated based on the transcript. If nothing should be updated, return empty array: []
        Do not include markdown or code fences, only the JSON array.

        Current Contact (JSON):
        #{contact_json}

        Meeting transcript:
        #{meeting_prompt}
        """

        case call_gemini(prompt) do
          {:ok, text} ->
            parse_contact_updates_response(text)

          {:error, _} = err ->
            err
        end
    end
  end

  defp parse_contact_updates_response(text) when is_binary(text) do
    trimmed =
      text
      |> String.trim()
      |> String.replace(~r/^```\w*\n?/, "")
      |> String.replace(~r/\n?```$/, "")
      |> String.trim()

    case Jason.decode(trimmed) do
      {:ok, list} when is_list(list) ->
        validated =
          list
          |> Enum.filter(&is_map/1)
          |> Enum.map(&validate_suggestion/1)
          |> Enum.reject(&is_nil/1)

        {:ok, validated}

      _ ->
        {:error, {:parsing_error, "AI did not return valid JSON array", text}}
    end
  end

  defp validate_suggestion(%{"field" => field, "suggested_value" => suggested} = m)
       when is_binary(field) do
    %{
      "field" => field,
      "current_value" => Map.get(m, "current_value"),
      "suggested_value" => suggested |> to_string(),
      "reason" => Map.get(m, "reason") || "From meeting"
    }
  end

  defp validate_suggestion(_), do: nil

  defp call_gemini(prompt_text) do
    api_key = Application.get_env(:social_scribe, :gemini_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, {:config_error, "Gemini API key is missing - set GEMINI_API_KEY env var"}}
    else
      path = "/#{@gemini_model}:generateContent?key=#{api_key}"

      payload = %{
        contents: [
          %{
            parts: [%{text: prompt_text}]
          }
        ]
      }

      case Tesla.post(client(), path, payload) do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          text_path = [
            "candidates",
            Access.at(0),
            "content",
            "parts",
            Access.at(0),
            "text"
          ]

          case get_in(body, text_path) do
            nil -> {:error, {:parsing_error, "No text content found in Gemini response", body}}
            text_content -> {:ok, text_content}
          end

        {:ok, %Tesla.Env{status: 429, body: error_body}} ->
          # Rate limited: wait and retry once (Gemini often suggests ~35s)
          wait_seconds = parse_retry_after_seconds(error_body) || 40
          Process.sleep(min(wait_seconds, 90) * 1000)
          case Tesla.post(client(), path, payload) do
            {:ok, %Tesla.Env{status: 200, body: body}} ->
              case get_in(body, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"]) do
                nil -> {:error, {:parsing_error, "No text content found in Gemini response", body}}
                text_content -> {:ok, text_content}
              end
            {:ok, %Tesla.Env{status: status, body: retry_body}} ->
              {:error, {:api_error, status, retry_body}}
            {:error, reason} ->
              {:error, {:http_error, reason}}
          end

        {:ok, %Tesla.Env{status: status, body: error_body}} ->
          {:error, {:api_error, status, error_body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end
  end

  defp client do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, @gemini_api_base_url},
      Tesla.Middleware.JSON
    ])
  end

  # Parse Gemini 429 body for retry delay (e.g. "35s" or "Please retry in 35.2s").
  defp parse_retry_after_seconds(%{"error" => err}), do: parse_retry_from_details(err) || parse_retry_from_message(err)
  defp parse_retry_after_seconds(_), do: nil

  defp parse_retry_from_details(%{"details" => details}) when is_list(details) do
    Enum.find_value(details, fn
      %{"@type" => "type.googleapis.com/google.rpc.RetryInfo", "retryDelay" => delay}
      when is_binary(delay) ->
        parse_retry_delay_string(delay)
      _ ->
        nil
    end)
  end
  defp parse_retry_from_details(_), do: nil

  defp parse_retry_from_message(%{"message" => msg}) when is_binary(msg) do
    case Regex.run(~r/retry in (\d+(?:\.\d+)?)s/i, msg) do
      [_, num] ->
        case Float.parse(num) do
          {f, _} -> ceil(f)
          :error -> nil
        end
      nil -> nil
    end
  end
  defp parse_retry_from_message(_), do: nil

  defp parse_retry_delay_string(str) do
    case Float.parse(String.trim(str, "sS")) do
      {sec, _} -> sec |> ceil()
      :error -> nil
    end
  end
end
