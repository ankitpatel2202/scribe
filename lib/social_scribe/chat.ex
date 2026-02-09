defmodule SocialScribe.Chat do
  @moduledoc """
  Context for the "Ask Anything" chat: sessions, messages, contact search,
  and answering questions using CRM contact data (HubSpot or Salesforce).
  """

  import Ecto.Query, warn: false

  alias SocialScribe.Repo
  alias SocialScribe.Accounts
  alias SocialScribe.Accounts.User
  alias SocialScribe.Chat.Session
  alias SocialScribe.Chat.Message
  alias SocialScribe.HubspotApi
  alias SocialScribe.SalesforceApi
  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.Meetings

  # ---------- Sessions ----------

  @doc "Creates a new chat session for the user."
  def create_session(%User{} = user, attrs \\ %{}) do
    attrs = Map.put(attrs, :user_id, user.id)
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Lists chat sessions for the user, newest first."
  def list_sessions(%User{} = user) do
    from(s in Session,
      where: s.user_id == ^user.id,
      order_by: [desc: s.updated_at],
      preload: [:messages]
    )
    |> Repo.all()
  end

  @doc "Gets a session by id; ensures it belongs to the user."
  def get_session!(%User{} = user, session_id) do
    from(s in Session,
      where: s.id == ^session_id and s.user_id == ^user.id,
      preload: [:messages]
    )
    |> Repo.one!()
    |> then(fn s -> %{s | messages: Enum.sort_by(s.messages, & &1.inserted_at)} end)
  end

  @doc "Gets a session by id or nil if not found / not owned."
  def get_session(%User{} = user, session_id) do
    from(s in Session,
      where: s.id == ^session_id and s.user_id == ^user.id,
      preload: [:messages]
    )
    |> Repo.one()
    |> case do
      nil -> nil
      s -> %{s | messages: Enum.sort_by(s.messages, & &1.inserted_at)}
    end
  end

  # ---------- Messages ----------

  @doc "Appends a user or assistant message to a session. sources (optional) is a list of %{provider, contact_id, contact_name} for assistant messages (used for Sources UI)."
  def add_message(%Session{} = session, role, content, tagged_contacts \\ [], sources \\ nil) when role in ["user", "assistant"] do
    attrs = %{
      session_id: session.id,
      role: role,
      content: content,
      tagged_contacts: %{"contacts" => List.wrap(tagged_contacts)}
    }

    attrs =
      if role == "assistant" && is_list(sources) && sources != [] do
        sources_serialized =
          Enum.map(sources, fn s ->
            %{
              "provider" => get_provider(s),
              "contact_id" => get_contact_id(s),
              "contact_name" => get_contact_name(s)
            }
          end)
        Map.put(attrs, :sources, %{"sources" => sources_serialized})
      else
        attrs
      end

    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  defp get_provider(%{"provider" => p}) when is_binary(p), do: p
  defp get_provider(%{provider: p}) when is_binary(p), do: p
  defp get_provider(_), do: nil

  defp get_contact_id(%{"id" => id}), do: to_string(id)
  defp get_contact_id(%{id: id}), do: to_string(id)
  defp get_contact_id(_), do: nil

  defp get_contact_name(%{"name" => n}), do: n
  defp get_contact_name(%{name: n}), do: n
  defp get_contact_name(_), do: nil

  # ---------- CRM resolution ----------

  @doc "Returns which CRM is connected: :hubspot, :salesforce, or nil."
  def connected_crm(%User{} = user) do
    cond do
      Accounts.get_user_hubspot_credential(user.id) -> :hubspot
      Accounts.get_crm_connection(user, "salesforce") -> :salesforce
      true -> nil
    end
  end

  @doc "Searches contacts in the user's connected CRM. Returns list of %{id, name, ...}."
  def search_contacts(%User{} = user, query) when is_binary(query) do
    query = String.trim(query)
    if query == "", do: {:ok, []}, else: do_search_contacts(user, query)
  end

  defp do_search_contacts(user, query) do
    case connected_crm(user) do
      :hubspot ->
        cred = Accounts.get_user_hubspot_credential(user.id)
        if cred do
          case HubspotApi.search_contacts(cred, query) do
            {:ok, contacts} -> {:ok, Enum.map(contacts, &hubspot_contact_to_summary/1)}
            err -> err
          end
        else
          {:ok, []}
        end

      :salesforce ->
        conn = Accounts.get_crm_connection(user, "salesforce")
        if conn do
          case SalesforceApi.search_contacts(conn, query) do
            {:ok, results} -> {:ok, Enum.map(results, &salesforce_contact_to_summary/1)}
            err -> err
          end
        else
          {:ok, []}
        end

      nil ->
        {:ok, []}
    end
  end

  defp hubspot_contact_to_summary(c) do
    %{
      "id" => to_string(c.id),
      "name" => c.display_name || [c.firstname, c.lastname] |> Enum.filter(& &1) |> Enum.join(" "),
      "email" => c.email,
      "provider" => "hubspot"
    }
  end

  defp salesforce_contact_to_summary(c) do
    %{
      "id" => c["id"],
      "name" => c["name"],
      "email" => c["email"],
      "provider" => "salesforce"
    }
  end

  @doc "Fetches full contact data for the given tagged contact (from search result)."
  def fetch_contact_data(%User{} = user, %{"id" => id, "provider" => "hubspot"}) do
    cred = Accounts.get_user_hubspot_credential(user.id)
    if cred do
      case HubspotApi.get_contact(cred, id) do
        {:ok, c} -> {:ok, hubspot_contact_to_map(c)}
        err -> err
      end
    else
      {:error, :no_connection}
    end
  end

  def fetch_contact_data(%User{} = user, %{"id" => id, "provider" => "salesforce"}) do
    conn = Accounts.get_crm_connection(user, "salesforce")
    if conn do
      case SalesforceApi.get_contact(conn, id) do
        {:ok, record} -> {:ok, record}
        err -> err
      end
    else
      {:error, :no_connection}
    end
  end

  def fetch_contact_data(_user, _), do: {:error, :invalid_contact}

  defp hubspot_contact_to_map(c) do
    %{
      "id" => to_string(c.id),
      "firstname" => c.firstname,
      "lastname" => c.lastname,
      "display_name" => c.display_name,
      "email" => c.email,
      "phone" => c.phone,
      "company" => c.company,
      "jobtitle" => c.jobtitle,
      "address" => c.address,
      "city" => c.city,
      "state" => c.state,
      "zip" => c.zip,
      "country" => c.country,
      "website" => c.website
    }
  end

  @doc """
  Answers a question using the given tagged contacts' data from the CRM.
  tagged_contacts: list of %{"id" => ..., "name" => ..., "provider" => ...} from search.
  Returns {:ok, %{answer: text, sources: list of source labels}} or {:error, reason}.
  """
  def ask_question(%User{} = user, question, tagged_contacts) when is_binary(question) do
    contact_data_list =
      tagged_contacts
      |> List.wrap()
      |> Enum.map(fn tc ->
        case fetch_contact_data(user, tc) do
          {:ok, data} -> data
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    sources =
      tagged_contacts
      |> List.wrap()
      |> Enum.map(fn tc -> tc["name"] || tc["id"] || "Contact" end)

    meeting_context = Meetings.get_user_meeting_context_for_ask(user)
    opts = if meeting_context != "", do: [meeting_context: meeting_context], else: []

    case AIContentGeneratorApi.generate_contact_question_answer(question, contact_data_list, opts) do
      {:ok, answer} ->
        {:ok, %{answer: answer, sources: sources}}

      err ->
        err
    end
  end
end
