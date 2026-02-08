defmodule SocialScribe.SalesforceApi do
  @moduledoc """
  Salesforce REST API client: token refresh, contact search, get/update contact.
  Uses instance_url and access_token from a CRM connection (Salesforce).
  """

  alias SocialScribe.Accounts
  require Logger

  @api_version "v59.0"

  defp salesforce_token_url do
    base = Application.get_env(:social_scribe, :salesforce_auth_base_url) || "https://login.salesforce.com"
    String.trim_trailing(base, "/") <> "/services/oauth2/token"
  end

  @doc """
  Returns a valid access token, refreshing the CRM connection if expired.
  """
  def get_valid_access_token(%Accounts.CrmConnection{} = conn) do
    if token_expired?(conn) do
      refresh_and_update(conn)
    else
      {:ok, conn.access_token}
    end
  end

  @doc """
  Searches Salesforce contacts by name or email. Returns a list of %{id, name, email, ...}.
  """
  def search_contacts(%Accounts.CrmConnection{} = conn, query_string) when is_binary(query_string) do
    with {:ok, token} <- get_valid_access_token(conn),
         base <- base_url(conn),
         # SOQL: search by Name or Email (escape single quotes for SOQL)
         escaped <- escape_soql_like(query_string),
         soql <- "SELECT Id, Name, FirstName, LastName, Email, Phone, Title FROM Contact WHERE Name LIKE '%#{escaped}%' OR Email LIKE '%#{escaped}%' ORDER BY Name LIMIT 25",
         encoded <- URI.encode_www_form(soql),
         url <- "#{base}/services/data/#{@api_version}/query?q=#{encoded}" do
      case get_with_token(url, token) do
        {:ok, %{"records" => records} = full} ->
          Logger.debug("SalesforceApi.search_contacts response: totalSize=#{Map.get(full, "totalSize", "?")}, records=#{length(records)}")
          result = Enum.map(records, &map_contact_summary/1)
          Logger.debug("SalesforceApi.search_contacts mapped result: #{inspect(result)}")
          {:ok, result}

        {:ok, %{"error" => code, "message" => msg} = body} ->
          Logger.debug("SalesforceApi.search_contacts error response: #{inspect(body)}")
          {:error, {:salesforce, code, msg}}

        {:error, reason} = err ->
          Logger.debug("SalesforceApi.search_contacts request failed: #{inspect(reason)}")
          err
      end
    end
  end

  @doc """
  Fetches a single Contact record by Id. Returns the full record as a map.
  """
  def get_contact(%Accounts.CrmConnection{} = conn, contact_id) when is_binary(contact_id) do
    with {:ok, token} <- get_valid_access_token(conn),
         base <- base_url(conn),
         url <- "#{base}/services/data/#{@api_version}/sobjects/Contact/#{contact_id}" do
      case get_with_token(url, token) do
        {:ok, body} when is_map(body) and not is_map_key(body, "error") ->
          Logger.debug("SalesforceApi.get_contact response for #{contact_id}: #{inspect(body)}")
          {:ok, body}

        {:ok, %{"errorCode" => code, "message" => msg} = body} ->
          Logger.debug("SalesforceApi.get_contact error response: #{inspect(body)}")
          {:error, {:salesforce, code, msg}}

        {:error, reason} = err ->
          Logger.debug("SalesforceApi.get_contact request failed for #{contact_id}: #{inspect(reason)}")
          err
      end
    end
  end

  @doc """
  Updates a Contact record with the given attributes. Attributes map keys should be Salesforce field API names (e.g. Phone, Email).
  """
  def update_contact(%Accounts.CrmConnection{} = conn, contact_id, attrs)
      when is_binary(contact_id) and is_map(attrs) do
    with {:ok, token} <- get_valid_access_token(conn),
         base <- base_url(conn),
         url <- "#{base}/services/data/#{@api_version}/sobjects/Contact/#{contact_id}" do
    case patch_with_token(url, token, attrs) do
      {:ok, 204} ->
        Logger.debug("SalesforceApi.update_contact success: contact_id=#{contact_id}, attrs=#{inspect(attrs)}")
        :ok

      {:error, reason} = err ->
        Logger.debug("SalesforceApi.update_contact failed: contact_id=#{contact_id}, reason=#{inspect(reason)}")
        err
    end
    end
  end

  defp token_expired?(conn) do
    case conn.expires_at do
      nil -> false
      dt -> DateTime.compare(DateTime.utc_now(), dt) != :lt
    end
  end

  defp refresh_and_update(conn) do
    case conn.refresh_token do
      nil ->
        {:error, :no_refresh_token}

      refresh_token ->
        case refresh_salesforce_token(conn, refresh_token) do
          {:ok, %{"access_token" => token, "instance_url" => instance_url}} ->
            attrs = %{
              access_token: token,
              instance_url: instance_url,
              expires_at: nil
            }

            case Accounts.update_crm_connection_tokens(conn, attrs) do
              {:ok, updated} -> {:ok, updated.access_token}
              {:error, _} -> {:ok, conn.access_token}
            end

          {:error, reason} ->
            Logger.warning("Salesforce token refresh failed: #{inspect(reason)}")
            # Use existing token as fallback; may still work
            {:ok, conn.access_token}
        end
    end
  end

  defp refresh_salesforce_token(_conn, refresh_token) do
    client_id = Application.get_env(:social_scribe, :salesforce_client_id)
    client_secret = Application.get_env(:social_scribe, :salesforce_client_secret)

    body = %{
      "grant_type" => "refresh_token",
      "refresh_token" => refresh_token,
      "client_id" => client_id,
      "client_secret" => client_secret
    }

    client =
      Tesla.client([
        {Tesla.Middleware.FormUrlencoded,
         encode: &Plug.Conn.Query.encode/1, decode: &Plug.Conn.Query.decode/1}
      ])

    case Tesla.post(client, salesforce_token_url(), body) do
      {:ok, %Tesla.Env{status: 200, body: body}} -> {:ok, body}
      {:ok, %Tesla.Env{status: _, body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp base_url(conn) do
    String.trim_trailing(conn.instance_url || "", "/")
  end

  # SOQL: escape single quote by doubling; sanitize for LIKE
  defp escape_soql_like(str) do
    str
    |> String.replace("'", "''")
    |> String.trim()
    |> String.slice(0, 100)
  end

  defp map_contact_summary(record) do
    %{
      "id" => record["Id"],
      "name" => record["Name"] || build_name(record),
      "email" => record["Email"],
      "phone" => record["Phone"],
      "firstName" => record["FirstName"],
      "lastName" => record["LastName"],
      "title" => record["Title"]
    }
  end

  defp build_name(%{"FirstName" => first, "LastName" => last}) do
    [first, last] |> Enum.filter(& &1) |> Enum.join(" ")
  end

  defp build_name(_), do: nil

  defp get_with_token(url, token) do
    client =
      Tesla.client([
        Tesla.Middleware.JSON,
        {Tesla.Middleware.Headers, [{"Authorization", "Bearer #{token}"}]}
      ])

    case Tesla.get(client, url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.debug("SalesforceApi GET non-200: status=#{status}, body=#{inspect(body)}")
        {:error, {status, body}}

      {:error, reason} ->
        Logger.debug("SalesforceApi GET request error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp patch_with_token(url, token, attrs) do
    client =
      Tesla.client([
        Tesla.Middleware.JSON,
        {Tesla.Middleware.Headers, [{"Authorization", "Bearer #{token}"}]}
      ])

    case Tesla.patch(client, url, attrs) do
      {:ok, %Tesla.Env{status: 204}} ->
        {:ok, 204}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.debug("SalesforceApi PATCH non-204: status=#{status}, body=#{inspect(body)}")
        {:error, {status, body}}

      {:error, reason} ->
        Logger.debug("SalesforceApi PATCH request error: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
