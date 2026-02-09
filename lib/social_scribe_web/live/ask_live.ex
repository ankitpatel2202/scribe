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
      |> assign(:cursor_position, nil)
      |> assign(:mention_start, nil)
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

  def handle_event("cursor_position", %{"position" => pos}, socket) do
    pos =
      cond do
        is_integer(pos) -> pos
        is_binary(pos) and pos != "" -> String.to_integer(pos)
        true -> nil
      end

    {:noreply, assign(socket, :cursor_position, pos)}
  end

  def handle_event("update_input", %{"text" => text}, socket) do
    socket = assign(socket, :input_text, text)
    cursor = socket.assigns.cursor_position || String.length(text)

    # Detect @mention: find last "@" before cursor and open contact search only for NEW mentions.
    # Don't open if the text after @ is an already-tagged contact (e.g. "@Ankit sing" after selecting Ankit).
    {socket, _} =
      if is_integer(cursor) and cursor >= 0 and cursor <= String.length(text) do
        before_cursor = String.slice(text, 0, cursor)
        case find_mention_start(before_cursor) do
          nil ->
            {socket, nil}
          start_idx ->
            rest_start = start_idx + 1
            rest_len = max(0, byte_size(text) - rest_start)
            query_part = text |> String.slice(rest_start, rest_len) |> String.split(~r/\s/) |> List.first() || ""

            # Skip opening if this @ is followed by an already-tagged contact name (stops search after selecting)
            if query_part_matches_tagged_contact?(query_part, socket.assigns.tagged_contacts) do
              {assign(socket, :contact_search_open, false), nil}
            else
              socket =
                socket
                |> assign(:mention_start, start_idx)
                |> assign(:contact_search_open, true)
                |> assign(:contact_search_query, query_part)
                |> then(fn s ->
                  if String.length(query_part) >= 2 do
                    send(self(), {:run_contact_search, query_part})
                    assign(s, :contact_search_loading, true)
                  else
                    assign(s, :contact_search_results, [])
                    assign(s, :contact_search_loading, false)
                  end
                end)
              {socket, start_idx}
            end
        end
      else
        {socket, nil}
      end

    {:noreply, socket}
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
  def handle_event("select_contact", %{"id" => id, "name" => name, "provider" => provider} = params, socket) do
    contact = %{"id" => id, "name" => name, "provider" => provider}
    tagged = socket.assigns.tagged_contacts
    tagged = if Enum.any?(tagged, fn t -> t["id"] == id end), do: tagged, else: tagged ++ [contact]

    # Use client-provided text when present (ensures we have what's actually in the textarea)
    text = params["text"]
    text = if is_binary(text) and text != "", do: text, else: socket.assigns.input_text
    query = socket.assigns.contact_search_query || ""

    # Find @ position: prefer exact "@" <> query in text (most reliable), else last valid @
    start_idx = find_at_index_for_query(text, query)

    {socket, new_text} =
      if is_integer(start_idx) and start_idx >= 0 and byte_size(text) > start_idx do
        len = byte_size(text)
        rest_start = start_idx + 1
        rest_len = max(0, len - rest_start)
        rest = String.slice(text, rest_start, rest_len)
        query_part = rest |> String.split(~r/\s/) |> List.first() || ""
        end_pos = min(start_idx + 1 + String.length(query_part), len)
        before = String.slice(text, 0, start_idx)
        after_len = max(0, len - end_pos)
        after_mention = String.slice(text, end_pos, after_len)
        new_text = before <> "@" <> name <> " " <> after_mention
        socket = socket
          |> assign(:input_text, new_text)
          |> assign(:mention_start, nil)
        {socket, new_text}
      else
        {socket, nil}
      end

    # Push value to client so textarea is updated even if a race overwrites the assign
    socket =
      if new_text do
        push_event(socket, "set_ask_input_value", %{value: new_text})
      else
        socket
      end

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
    {:noreply, socket |> assign(:contact_search_open, false) |> assign(:mention_start, nil)}
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

  # True if the text after @ (query_part) is the start of an already-tagged contact name.
  # Stops the dropdown from reopening when user keeps typing after selecting a contact.
  defp query_part_matches_tagged_contact?(_query_part, []), do: false

  defp query_part_matches_tagged_contact?(query_part, tagged_contacts) when is_binary(query_part) do
    name = String.trim(query_part)
    Enum.any?(tagged_contacts, fn t ->
      contact_name = t["name"] || t[:name] || ""
      name != "" and (contact_name == name or String.starts_with?(contact_name, name))
    end)
  end

  defp find_mention_start(before_cursor) do
    parts = String.split(before_cursor, "@")
    if length(parts) <= 1, do: nil, else: last_at_index(parts, before_cursor)
  end

  defp last_at_index(parts, before_cursor) do
    before_last = parts |> Enum.drop(-1) |> Enum.join("@")
    idx = byte_size(before_last)
    before_at = if idx > 0, do: String.slice(before_cursor, idx - 1, 1), else: " "
    if before_at in [" ", "\n"] or idx == 0, do: idx, else: nil
  end

  # Find the last @ in full text that starts a mention (at start or after space/newline).
  defp find_last_mention_position(""), do: nil
  defp find_last_mention_position(text) when is_binary(text) do
    parts = String.split(text, "@")
    if length(parts) <= 1 do
      nil
    else
      before_last = parts |> Enum.take(length(parts) - 1) |> Enum.join("@")
      idx = byte_size(before_last)
      before_at = if idx > 0, do: String.slice(text, idx - 1, 1), else: " "
      if before_at in [" ", "\n", "\r"] or idx == 0, do: idx, else: nil
    end
  end

  # Find start index of "@query" in text (last occurrence). Most reliable when we have the exact query.
  defp find_at_index_for_query(text, query) when is_binary(text) and is_binary(query) and query != "" do
    needle = "@" <> query
    case last_index_of(text, needle) do
      nil -> find_last_mention_position(text)
      idx -> idx
    end
  end
  defp find_at_index_for_query(text, _), do: find_last_mention_position(text)

  defp last_index_of(haystack, needle) when is_binary(haystack) and is_binary(needle) do
    len = byte_size(needle)
    if len == 0 or byte_size(haystack) < len do
      nil
    else
      last_index_of(haystack, needle, 0, nil)
    end
  end

  defp last_index_of(haystack, needle, start, last) do
    case :binary.match(haystack, needle, scope: {start, byte_size(haystack) - start}) do
      {idx, _} -> last_index_of(haystack, needle, idx + 1, idx)
      :nomatch -> last
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
