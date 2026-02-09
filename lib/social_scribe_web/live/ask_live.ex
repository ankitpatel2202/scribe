defmodule SocialScribeWeb.AskLive do
  @moduledoc "Ask Anything chat: ask questions about CRM contacts (HubSpot or Salesforce)."
  use SocialScribeWeb, :live_view

  alias SocialScribe.Chat

  attr :content, :string, required: true
  attr :tagged_contacts, :list, default: []

  defp message_with_tags(assigns) do
    assigns = assign(assigns, :segments, segments_from_content(assigns.content, assigns.tagged_contacts))
    ~H"""
    <span>
      <%= for seg <- @segments do %>
        <%= if seg.type == :tag do %>
          <span class="inline-flex items-center gap-0.5 rounded bg-gray-300/80 px-1 text-gray-900">
            <.icon name="hero-user" class="w-3.5 h-3.5 text-gray-600" />
            <%= seg.name %>
          </span>
        <% else %>
          <%= seg.value %>
        <% end %>
      <% end %>
    </span>
    """
  end

  defp segments_from_content(content, tagged) when is_binary(content) do
    names = Enum.map(tagged, fn tc -> tc["name"] || tc["id"] || "" end) |> Enum.reject(&(&1 == ""))
    if names == [] do
      [%{type: :text, value: content}]
    else
      # Split by @Name patterns and build segments
      pattern = ~r/@(#{Enum.map_join(names, "|", &Regex.escape/1)})/i
      parts = Regex.split(pattern, content, include_captures: true)
      Enum.flat_map(parts, fn
        "" -> []
        part ->
          if byte_size(part) > 0 and String.starts_with?(part, "@") do
            [%{type: :tag, name: String.trim_leading(part, "@")}]
          else
            [%{type: :text, value: part}]
          end
      end)
    end
  end
  defp segments_from_content(_, _), do: [%{type: :text, value: ""}]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    crm = Chat.connected_crm(user)
    session = get_or_create_session(user)

    socket =
      socket
      |> assign(:page_title, "Ask Anything")
      |> assign(:session, session)
      |> assign(:messages, session.messages)
      |> assign(:crm_connected, crm != nil)
      |> assign(:crm_provider, crm)
      |> assign(:input_text, "")
      |> assign(:tagged_contacts, [])
      |> assign(:contact_search_query, "")
      |> assign(:contact_search_results, [])
      |> assign(:contact_search_open, false)
      |> assign(:contact_search_loading, false)
      |> assign(:sending, false)
      |> assign(:active_tab, :chat)
      |> assign(:history_sessions, [])
      |> assign(:error, nil)
      |> load_history_sessions(user)

    {:ok, socket}
  end

  defp get_or_create_session(user) do
    case Chat.list_sessions(user) do
      [latest | _] -> Chat.get_session!(user, latest.id)
      [] -> {:ok, s} = Chat.create_session(user); Chat.get_session!(user, s.id)
    end
  end

  defp load_history_sessions(socket, user) do
    sessions = Chat.list_sessions(user)
    assign(socket, :history_sessions, sessions)
  end

  @impl true
  def handle_params(params, _uri, socket) do
    session_id = params["session_id"]
    user = socket.assigns.current_user

    socket =
      if session_id && session_id != "" do
        case Chat.get_session(user, session_id) do
          nil -> socket
          session ->
            socket
            |> assign(:session, session)
            |> assign(:messages, session.messages)
        end
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("send_message", %{"text" => text}, socket) do
    text = String.trim(text)
    if text == "" do
      {:noreply, socket}
    else
      user = socket.assigns.current_user
      session = socket.assigns.session
      tagged = socket.assigns.tagged_contacts

      socket =
        socket
        |> assign(:sending, true)
        |> assign(:input_text, "")
        |> assign(:error, nil)

      case Chat.add_message(session, "user", text, tagged) do
        {:ok, _msg} ->
          session = Chat.get_session!(user, session.id)
          socket = assign(socket, :messages, session.messages)

          case Chat.ask_question(user, text, tagged) do
            {:ok, %{answer: answer, sources: _sources}} ->
              Chat.add_message(session, "assistant", answer, [], tagged)
              session = Chat.get_session!(user, session.id)
              {:noreply,
               socket
               |> assign(:messages, session.messages)
               |> assign(:sending, false)}

            {:error, reason} ->
              error_msg = error_message(reason)
              Chat.add_message(session, "assistant", "Sorry, I couldn't answer that: #{error_msg}. Please check your CRM connection and try again.", [], tagged)
              session = Chat.get_session!(user, session.id)
              {:noreply,
               socket
               |> assign(:messages, session.messages)
               |> assign(:sending, false)
               |> assign(:error, error_msg)}
          end

        {:error, _} ->
          {:noreply, assign(socket, :sending, false)}
      end
    end
  end

  def handle_event("send_message", _, socket), do: {:noreply, socket}

  def handle_event("update_input", %{"text" => text}, socket) do
    {:noreply, assign(socket, :input_text, text)}
  end

  @impl true
  def handle_event("contact_search", %{"value" => query}, socket) do
    query = String.trim(query)

    if String.length(query) >= 2 do
      send(self(), {:run_contact_search, query})
      {:noreply,
       socket
       |> assign(:contact_search_query, query)
       |> assign(:contact_search_open, true)
       |> assign(:contact_search_loading, true)}
    else
      {:noreply,
       socket
       |> assign(:contact_search_query, query)
       |> assign(:contact_search_results, [])
       |> assign(:contact_search_open, query != "")
       |> assign(:contact_search_loading, false)}
    end
  end

  @impl true
  def handle_event("select_contact", %{"id" => id, "name" => name, "provider" => provider}, socket) do
    contact = %{"id" => id, "name" => name, "provider" => provider}
    tagged = socket.assigns.tagged_contacts
    tagged = if Enum.any?(tagged, fn t -> t["id"] == id end), do: tagged, else: tagged ++ [contact]

    {:noreply,
     socket
     |> assign(:tagged_contacts, tagged)
     |> assign(:contact_search_open, false)
     |> assign(:contact_search_results, [])
     |> assign(:contact_search_query, "")}
  end

  @impl true
  def handle_event("remove_tag", %{"id" => id}, socket) do
    tagged = Enum.reject(socket.assigns.tagged_contacts, fn t -> t["id"] == id end)
    {:noreply, assign(socket, :tagged_contacts, tagged)}
  end

  @impl true
  def handle_event("open_contact_search", _, socket) do
    {:noreply, assign(socket, :contact_search_open, true)}
  end

  @impl true
  def handle_event("close_contact_search", _, socket) do
    {:noreply, assign(socket, :contact_search_open, false)}
  end

  @impl true
  def handle_event("new_chat", _, socket) do
    user = socket.assigns.current_user
    {:ok, new_session} = Chat.create_session(user)
    session = Chat.get_session!(user, new_session.id)

    {:noreply,
     socket
     |> assign(:session, session)
     |> assign(:messages, session.messages)
     |> assign(:tagged_contacts, [])
     |> assign(:input_text, "")
     |> push_patch(to: ~p"/dashboard/ask")}
  end

  @impl true
  def handle_event("tab", %{"tab" => "history"}, socket) do
    user = socket.assigns.current_user
    sessions = Chat.list_sessions(user)
    {:noreply,
     socket
     |> assign(:active_tab, :history)
     |> assign(:history_sessions, sessions)}
  end

  def handle_event("tab", %{"tab" => "chat"}, socket) do
    {:noreply, assign(socket, :active_tab, :chat)}
  end

  @impl true
  def handle_event("load_session", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    case Chat.get_session(user, id) do
      nil -> {:noreply, socket}
      session ->
        {:noreply,
         socket
         |> assign(:session, session)
         |> assign(:messages, session.messages)
         |> assign(:active_tab, :chat)
         |> push_patch(to: ~p"/dashboard/ask")}
    end
  end

  def tagged_list_for(msg), do: SocialScribe.Chat.Message.tagged_contacts_list(msg)

  def sources_list_for(msg), do: SocialScribe.Chat.Message.sources_list(msg)

  def provider_logo_path("hubspot"), do: "/images/providers/hubspot.svg"
  def provider_logo_path("salesforce"), do: "/images/providers/salesforce.png"
  def provider_logo_path(_), do: nil

  defp error_message({:config_error, _}), do: "AI is not configured."
  defp error_message(:no_connection), do: "No CRM connected."
  defp error_message({:api_error, status, _}), do: "Service error (#{status})."
  defp error_message(_), do: "Something went wrong."

  @impl true
  def handle_info({:run_contact_search, query}, socket) do
    user = socket.assigns.current_user

    results =
      case Chat.search_contacts(user, query) do
      {:ok, list} -> list
      _ -> []
    end

    {:noreply,
     socket
     |> assign(:contact_search_results, results)
     |> assign(:contact_search_loading, false)}
  end
end
