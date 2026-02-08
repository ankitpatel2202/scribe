defmodule SocialScribeWeb.SalesforceAuthController do
  use SocialScribeWeb, :controller

  alias SocialScribe.Accounts
  require Logger

  @doc """
  Redirects the logged-in user to Salesforce to authorize the Connected App.
  Uses PKCE (code_challenge) as required by Salesforce.
  """
  def request(conn, _params) do
    user = conn.assigns.current_user
    state = generate_state()
    {code_verifier, code_challenge} = generate_pkce()

    conn
    |> put_session(:salesforce_oauth_state, state)
    |> put_session(:salesforce_oauth_user_id, user.id)
    |> put_session(:salesforce_oauth_code_verifier, code_verifier)
    |> redirect(external: authorize_url(state, code_challenge))
  end

  @doc """
  Handles the callback from Salesforce: exchanges code for tokens and stores the CRM connection.
  """
  def callback(conn, %{"code" => code, "state" => state}) do
    code_verifier = get_session(conn, :salesforce_oauth_code_verifier)

    with :ok <- verify_state(conn, state),
         user_id when is_integer(user_id) <- get_session(conn, :salesforce_oauth_user_id),
         {:ok, user} <- fetch_user(user_id),
         {:ok, token_response} <- exchange_code_for_token(code, code_verifier),
         {:ok, _connection} <- upsert_connection(user, token_response) do
      conn
      |> delete_session(:salesforce_oauth_state)
      |> delete_session(:salesforce_oauth_user_id)
      |> delete_session(:salesforce_oauth_code_verifier)
      |> put_flash(:info, "Salesforce connected successfully.")
      |> redirect(to: ~p"/dashboard/settings")
    else
      :invalid_state ->
        conn
        |> put_flash(:error, "Invalid OAuth state. Please try connecting again.")
        |> redirect(to: ~p"/dashboard/settings")

      nil ->
        conn
        |> put_flash(:error, "Session expired. Please log in and try again.")
        |> redirect(to: ~p"/dashboard/settings")

      {:error, :user_not_found} ->
        conn
        |> put_flash(:error, "User not found.")
        |> redirect(to: ~p"/dashboard/settings")

      {:error, reason} ->
        Logger.error("Salesforce OAuth token exchange failed: #{inspect(reason)}")
        conn
        |> put_flash(:error, "Could not connect to Salesforce. Please try again.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Salesforce did not return an authorization code.")
    |> redirect(to: ~p"/dashboard/settings")
  end

  defp generate_state do
    24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp verify_state(conn, state) do
    case get_session(conn, :salesforce_oauth_state) do
      ^state -> :ok
      _ -> :invalid_state
    end
  end

  # PKCE: code_verifier (random), code_challenge = base64url(sha256(code_verifier))
  defp generate_pkce do
    code_verifier = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    code_challenge = :crypto.hash(:sha256, code_verifier) |> Base.url_encode64(padding: false)
    {code_verifier, code_challenge}
  end

  defp maybe_add_code_verifier(body, nil), do: body
  defp maybe_add_code_verifier(body, ""), do: body
  defp maybe_add_code_verifier(body, code_verifier) when is_binary(code_verifier) do
    Map.put(body, "code_verifier", code_verifier)
  end

  defp fetch_user(user_id) do
    try do
      {:ok, Accounts.get_user!(user_id)}
    rescue
      Ecto.NoResultsError -> {:error, :user_not_found}
    end
  end

  defp authorize_url(state, code_challenge) do
    base = Application.get_env(:social_scribe, :salesforce_auth_base_url) || "https://login.salesforce.com"
    client_id = Application.get_env(:social_scribe, :salesforce_client_id)
    redirect_uri = Application.get_env(:social_scribe, :salesforce_redirect_uri)

    params =
      URI.encode_query(%{
        "response_type" => "code",
        "client_id" => client_id,
        "redirect_uri" => redirect_uri,
        "state" => state,
        "code_challenge" => code_challenge,
        "code_challenge_method" => "S256"
      })

    base = String.trim_trailing(base, "/")
    "#{base}/services/oauth2/authorize?#{params}"
  end

  defp exchange_code_for_token(code, code_verifier) do
    base = Application.get_env(:social_scribe, :salesforce_auth_base_url) || "https://login.salesforce.com"
    token_url = String.trim_trailing(base, "/") <> "/services/oauth2/token"
    client_id = Application.get_env(:social_scribe, :salesforce_client_id)
    client_secret = Application.get_env(:social_scribe, :salesforce_client_secret)
    redirect_uri = Application.get_env(:social_scribe, :salesforce_redirect_uri)

    body =
      %{
        "grant_type" => "authorization_code",
        "code" => code,
        "redirect_uri" => redirect_uri,
        "client_id" => client_id,
        "client_secret" => client_secret
      }
      |> maybe_add_code_verifier(code_verifier)

    client =
      Tesla.client([
        {Tesla.Middleware.FormUrlencoded,
         encode: &Plug.Conn.Query.encode/1, decode: &Plug.Conn.Query.decode/1}
      ])

    case Tesla.post(client, token_url, body) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        case decode_token_response(response_body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} = err -> err
        end

      {:ok, %Tesla.Env{status: status, body: response_body}} ->
        {:error, {:token_exchange, status, response_body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp decode_token_response(body) when is_map(body), do: {:ok, body}
  defp decode_token_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, :invalid_json_response}
    end
  end
  defp decode_token_response(_), do: {:error, :invalid_json_response}

  defp upsert_connection(user, %{
         "access_token" => access_token,
         "refresh_token" => refresh_token,
         "instance_url" => instance_url,
         "id" => id_url
       }) do
    # Parse identity URL to get user id; optional: fetch user info for email
    uid = extract_uid_from_identity_url(id_url)

    attrs = %{
      uid: uid,
      email: nil,
      access_token: access_token,
      refresh_token: refresh_token,
      instance_url: instance_url,
      expires_at: nil
    }

    Accounts.upsert_crm_connection(user, "salesforce", attrs)
  end

  defp upsert_connection(user, %{
         "access_token" => access_token,
         "instance_url" => instance_url,
         "id" => id_url
       }) do
    uid = extract_uid_from_identity_url(id_url)

    attrs = %{
      uid: uid,
      email: nil,
      access_token: access_token,
      refresh_token: nil,
      instance_url: instance_url,
      expires_at: nil
    }

    Accounts.upsert_crm_connection(user, "salesforce", attrs)
  end

  defp extract_uid_from_identity_url(url) when is_binary(url) do
    # Identity URL format: https://login.salesforce.com/id/00D.../005...
    url
  end
end
