defmodule SocialScribe.Facebook do
  @behaviour SocialScribe.FacebookApi

  require Logger

  @base_url "https://graph.facebook.com/v22.0"

  @impl SocialScribe.FacebookApi
  def post_message_to_page(page_id, page_access_token, message) do
    body_params = %{
      message: message,
      access_token: page_access_token
    }

    case Tesla.post(client(), "/#{page_id}/feed", body_params) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        Logger.info(
          "Successfully posted to Facebook Page #{page_id}. Response ID: #{response_body["id"]}"
        )

        {:ok, response_body}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        Logger.error(
          "Facebook Page Post API Error (Page ID: #{page_id}, Status: #{status}): #{inspect(error_body)}"
        )

        message = get_in(error_body, ["error", "message"]) || "Unknown API error"
        {:error, {:api_error_posting, status, message, error_body}}

      {:error, reason} ->
        Logger.error("Facebook Page Post HTTP Error (Page ID: #{page_id}): #{inspect(reason)}")
        {:error, {:http_error_posting, reason}}
    end
  end

  @impl SocialScribe.FacebookApi
  def fetch_user_pages(user_id, user_access_token) do
    case Tesla.get(client(), "/#{user_id}/accounts?access_token=#{user_access_token}") do
      {:ok, %Tesla.Env{status: 200, body: %{"data" => pages_data}}} ->
        valid_pages =
          Enum.filter(pages_data, fn page ->
            Enum.member?(page["tasks"] || [], "CREATE_CONTENT") ||
              Enum.member?(page["tasks"] || [], "MANAGE")
          end)
          |> Enum.map(fn page ->
            %{
              id: page["id"],
              name: page["name"],
              category: page["category"],
              page_access_token: page["access_token"]
            }
          end)

        {:ok, valid_pages}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Failed to fetch user pages: #{status} - #{inspect(body)}"}
    end
  end

  defp client do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, @base_url},
      Tesla.Middleware.JSON
    ])
  end
end
