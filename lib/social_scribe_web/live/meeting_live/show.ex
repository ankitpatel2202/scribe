defmodule SocialScribeWeb.MeetingLive.Show do
  use SocialScribeWeb, :live_view

  import SocialScribeWeb.PlatformLogo
  import SocialScribeWeb.ClipboardButton
  import SocialScribeWeb.ModalComponents, only: [hubspot_modal: 1]

  alias SocialScribe.Meetings
  alias SocialScribe.Automations
  alias SocialScribe.Accounts
  alias SocialScribe.HubspotApiBehaviour, as: HubspotApi
  alias SocialScribe.HubspotSuggestions
  
  alias SocialScribe.SalesforceApi
  alias SocialScribe.AIContentGeneratorApi

  @impl true
  def mount(%{"id" => meeting_id}, _session, socket) do
    meeting = Meetings.get_meeting_with_details(meeting_id)

    user_has_automations =
      Automations.list_active_user_automations(socket.assigns.current_user.id)
      |> length()
      |> Kernel.>(0)

    automation_results = Automations.list_automation_results_for_meeting(meeting_id)

    if meeting.calendar_event.user_id != socket.assigns.current_user.id do
      socket =
        socket
        |> put_flash(:error, "You do not have permission to view this meeting.")
        |> redirect(to: ~p"/dashboard/meetings")

      {:error, socket}
    else
      hubspot_credential = Accounts.get_user_hubspot_credential(socket.assigns.current_user.id)

      socket =
        socket
        |> assign(:page_title, "Meeting Details: #{meeting.title}")
        |> assign(:meeting, meeting)
        |> assign(:automation_results, automation_results)
        |> assign(:user_has_automations, user_has_automations)
        |> assign(:hubspot_credential, hubspot_credential)
        |> assign(
          :follow_up_email_form,
          to_form(%{
            "follow_up_email" => ""
          })
        )
        |> assign(:salesforce_connection, nil)
        |> assign(:contact_search_query, "")
        |> assign(:contact_results, [])
        |> assign(:selected_contact, nil)
        |> assign(:contact_record, nil)
        |> assign(:suggestions, [])
        |> assign(:loading_suggestions, false)
        |> assign(:suggestions_error, nil)
        |> assign(:update_success, nil)
        |> assign(:crm_contact_search_form, to_form(%{"query" => ""}))

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"id" => _id}, _uri, %{assigns: %{live_action: :crm_contact}} = socket) do
    salesforce_connection = Accounts.get_crm_connection(socket.assigns.current_user, "salesforce")

    socket =
      socket
      |> assign(:salesforce_connection, salesforce_connection)
      |> assign(:contact_results, [])
      |> assign(:selected_contact, nil)
      |> assign(:contact_record, nil)
      |> assign(:suggestions, [])
      |> assign(:loading_suggestions, false)
      |> assign(:suggestions_error, nil)
      |> assign(:update_success, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_params(%{"automation_result_id" => automation_result_id}, _uri, socket) do
    automation_result = Automations.get_automation_result!(automation_result_id)
    automation = Automations.get_automation!(automation_result.automation_id)

    socket =
      socket
      |> assign(:automation_result, automation_result)
      |> assign(:automation, automation)

    {:noreply, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate-follow-up-email", params, socket) do
    socket =
      socket
      |> assign(:follow_up_email_form, to_form(params))

    {:noreply, socket}
  end

  @impl true
  def handle_event("search_contacts", %{"query" => query}, socket) do
    query = String.trim(query)
    result = do_search_contacts(socket.assigns.salesforce_connection, query)

    socket =
      socket
      |> assign(:contact_search_query, query)
      |> assign(:contact_results, result)
      |> assign(:crm_contact_search_form, to_form(%{"query" => query}))

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_contact", %{"contact_id" => contact_id}, socket) do
    summary =
      Enum.find(socket.assigns.contact_results, fn c -> c["id"] == contact_id end)

    socket =
      socket
      |> assign(:selected_contact, summary)
      |> assign(:loading_suggestions, true)

    send(self(), {:load_contact_and_suggest, contact_id})

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_contact", _params, socket) do
    socket =
      socket
      |> assign(:selected_contact, nil)
      |> assign(:contact_record, nil)
      |> assign(:suggestions, [])
      |> assign(:loading_suggestions, false)
      |> assign(:suggestions_error, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("apply_suggestions", %{"fields" => fields}, socket) do
    fields = List.wrap(fields) |> Enum.filter(&(is_binary(&1) and &1 != ""))
    apply_suggestions_to_salesforce(socket, fields)
  end

  @impl true
  def handle_info({:hubspot_search, query, credential}, socket) do
    case HubspotApi.search_contacts(credential, query) do
      {:ok, contacts} ->
        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          contacts: contacts,
          searching: false
        )

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          error: "Failed to search contacts: #{inspect(reason)}",
          searching: false
        )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:generate_suggestions, contact, meeting, _credential}, socket) do
    case HubspotSuggestions.generate_suggestions_from_meeting(meeting) do
      {:ok, suggestions} ->
        merged = HubspotSuggestions.merge_with_contact(suggestions, normalize_contact(contact))

        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          step: :suggestions,
          suggestions: merged,
          loading: false
        )

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          error: "Failed to generate suggestions: #{inspect(reason)}",
          loading: false
        )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:apply_hubspot_updates, updates, contact, credential}, socket) do
    case HubspotApi.update_contact(credential, contact.id, updates) do
      {:ok, _updated_contact} ->
        socket =
          socket
          |> put_flash(:info, "Successfully updated #{map_size(updates)} field(s) in HubSpot")
          |> push_patch(to: ~p"/dashboard/meetings/#{socket.assigns.meeting}")

        {:noreply, socket}

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          error: "Failed to update contact: #{inspect(reason)}",
          loading: false
        )

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:load_contact_and_suggest, contact_id}, socket) do
    conn = socket.assigns.salesforce_connection
    meeting = socket.assigns.meeting

    result =
      with {:ok, record} <- SalesforceApi.get_contact(conn, contact_id),
           {:ok, suggestions} <-
             AIContentGeneratorApi.generate_salesforce_contact_updates(meeting, record) do
        summary = contact_summary_from_record(record)

        {:ok,
         %{
           record: record,
           suggestions: merge_current_values(record, suggestions),
           summary: summary
         }}
      else
        {:error, reason} -> {:error, reason}
      end

    socket =
      case result do
        {:ok, %{record: record, suggestions: suggestions, summary: summary}} ->
          socket
          |> assign(:contact_record, record)
          |> assign(:selected_contact, summary)
          |> assign(:suggestions, suggestions)
          |> assign(:loading_suggestions, false)
          |> assign(:suggestions_error, nil)

        {:error, reason} ->
          error_message = suggestions_error_message(reason)
          socket
          |> put_flash(:error, error_message)
          |> assign(:loading_suggestions, false)
          |> assign(:suggestions_error, error_message)
      end

    {:noreply, socket}
  end

  defp suggestions_error_message({:api_error, 429, _body}) do
    "AI is temporarily rate limited. Please wait a minute and try again (select the contact again)."
  end

  defp suggestions_error_message({:api_error, status, _body}) when is_integer(status) do
    "AI service error (#{status}). Please try again later."
  end

  defp suggestions_error_message(:no_transcript) do
    "No meeting transcript available to generate suggestions."
  end

  defp suggestions_error_message({:config_error, _}) do
    "AI is not configured. Set GEMINI_API_KEY in your environment."
  end

  defp suggestions_error_message(_reason) do
    "Could not load contact or generate suggestions. Please try again."
  end

  defp contact_summary_from_record(record) when is_map(record) do
    name =
      record["Name"] ||
        [record["FirstName"], record["LastName"]]
        |> Enum.filter(& &1)
        |> Enum.join(" ")

    %{
      "id" => record["Id"],
      "name" => name,
      "email" => record["Email"],
      "phone" => record["Phone"],
      "firstName" => record["FirstName"],
      "lastName" => record["LastName"],
      "title" => record["Title"]
    }
  end

  defp normalize_contact(contact) do
    # Contact is already formatted with atom keys from HubspotApi.format_contact
    contact
  end

  defp do_search_contacts(nil, _query), do: []
  defp do_search_contacts(_conn, ""), do: []

  defp do_search_contacts(conn, query) do
    case SalesforceApi.search_contacts(conn, query) do
      {:ok, results} -> results
      {:error, _} -> []
    end
  end

  defp merge_current_values(contact_record, suggestions) when is_list(suggestions) do
    Enum.map(suggestions, fn s ->
      field = s["field"]
      current = Map.get(contact_record, field) || s["current_value"]
      Map.put(s, "current_value", current)
    end)
  end

  defp apply_suggestions_to_salesforce(socket, fields) do
    conn = socket.assigns.salesforce_connection
    contact_id = socket.assigns.contact_record["Id"]
    suggestions = socket.assigns.suggestions

    attrs =
      suggestions
      |> Enum.filter(fn s -> s["field"] in fields end)
      |> Map.new(fn s -> {s["field"], s["suggested_value"]} end)

    if map_size(attrs) == 0 do
      {:noreply, put_flash(socket, :error, "No updates selected.")}
    else
      case SalesforceApi.update_contact(conn, contact_id, attrs) do
        :ok ->
          field_count = map_size(attrs)
          success_message = "Success! #{field_count} field(s) updated in Salesforce."
          socket
          |> put_flash(:info, success_message)
          |> assign(:update_success, success_message)
          |> then(fn s -> {:noreply, s} end)

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update Salesforce contact.")}
      end
    end
  end

  def format_contact_value(nil), do: "No existing value"
  def format_contact_value(""), do: "No existing value"
  def format_contact_value(val) when is_binary(val), do: val
  def format_contact_value(val), do: to_string(val)

  @salesforce_field_labels %{
    "FirstName" => "First name",
    "LastName" => "Last name",
    "Email" => "Email",
    "Phone" => "Phone",
    "Title" => "Title",
    "Department" => "Department",
    "Description" => "Description",
    "MailingStreet" => "Mailing street",
    "MailingCity" => "Mailing city",
    "MailingState" => "Mailing state",
    "MailingPostalCode" => "Mailing postal code",
    "MailingCountry" => "Mailing country"
  }
  def salesforce_field_label(field) when is_binary(field) do
    Map.get(@salesforce_field_labels, field) || field
  end

  def contact_initials(contact) when is_map(contact) do
    first = contact["FirstName"] || contact["firstName"]
    last = contact["LastName"] || contact["lastName"]
    name = contact["name"]

    cond do
      is_binary(first) and is_binary(last) ->
        String.first(first) <> String.first(last) |> String.upcase()

      is_binary(name) and name != "" ->
        name
        |> String.split(" ", parts: 2)
        |> Enum.map(&String.first/1)
        |> Enum.join()
        |> String.upcase()
        |> String.slice(0, 2)

      true ->
        "?"
    end
  end

  defp format_duration(nil), do: "N/A"

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)

    cond do
      minutes > 0 && remaining_seconds > 0 -> "#{minutes} min #{remaining_seconds} sec"
      minutes > 0 -> "#{minutes} min"
      seconds > 0 -> "#{seconds} sec"
      true -> "Less than a second"
    end
  end

  attr :meeting_transcript, :map, required: true

  defp transcript_content(assigns) do
    has_transcript =
      assigns.meeting_transcript &&
        assigns.meeting_transcript.content &&
        Map.get(assigns.meeting_transcript.content, "data") &&
        Enum.any?(Map.get(assigns.meeting_transcript.content, "data"))

    assigns =
      assigns
      |> assign(:has_transcript, has_transcript)

    ~H"""
    <div class="bg-white shadow-xl rounded-lg p-6 md:p-8">
      <h2 class="text-2xl font-semibold mb-4 text-slate-700">
        Meeting Transcript
      </h2>
      <div class="prose prose-sm sm:prose max-w-none h-96 overflow-y-auto pr-2">
        <%= if @has_transcript do %>
          <div :for={segment <- @meeting_transcript.content["data"]} class="mb-3">
            <p>
              <span class="font-semibold text-indigo-600">
                {segment["speaker"] || "Unknown Speaker"}:
              </span>
              {Enum.map_join(segment["words"] || [], " ", & &1["text"])}
            </p>
          </div>
        <% else %>
          <p class="text-slate-500">
            Transcript not available for this meeting.
          </p>
        <% end %>
      </div>
    </div>
    """
  end
end
