defmodule SocialScribe.ChatTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.Chat
  alias SocialScribe.Chat.Message
  alias SocialScribe.Chat.Session

  import SocialScribe.AccountsFixtures
  import Mox

  setup :verify_on_exit!

  describe "sessions" do
    test "create_session/2 creates a session for the user" do
      user = user_fixture()
      assert {:ok, %Session{} = session} = Chat.create_session(user)
      assert session.user_id == user.id
      assert session.title == "New chat"
    end

    test "create_session/2 accepts custom title" do
      user = user_fixture()
      assert {:ok, %Session{} = session} = Chat.create_session(user, %{title: "My chat"})
      assert session.title == "My chat"
    end

    test "list_sessions/1 returns sessions newest first" do
      user = user_fixture()
      {:ok, _s1} = Chat.create_session(user)
      {:ok, s2} = Chat.create_session(user)
      sessions = Chat.list_sessions(user)
      assert length(sessions) == 2
      assert s2.id in Enum.map(sessions, & &1.id)
    end

    test "get_session!/2 returns session when owned by user" do
      user = user_fixture()
      {:ok, session} = Chat.create_session(user)
      got = Chat.get_session!(user, session.id)
      assert got.id == session.id
      assert got.messages == []
    end

    test "get_session!/2 raises when session not found or not owned" do
      user = user_fixture()
      assert_raise Ecto.NoResultsError, fn ->
        Chat.get_session!(user, 99_999)
      end
    end

    test "get_session/2 returns nil when not found" do
      user = user_fixture()
      assert Chat.get_session(user, 99_999) == nil
    end

    test "get_session/2 returns session when found" do
      user = user_fixture()
      {:ok, session} = Chat.create_session(user)
      got = Chat.get_session(user, session.id)
      assert got.id == session.id
    end
  end

  describe "messages" do
    setup do
      user = user_fixture()
      {:ok, session} = Chat.create_session(user)
      session = Chat.get_session!(user, session.id)
      %{user: user, session: session}
    end

    test "add_message/4 inserts user message", %{session: session} do
      assert {:ok, %Message{} = msg} = Chat.add_message(session, "user", "Hello")
      assert msg.role == "user"
      assert msg.content == "Hello"
      assert msg.session_id == session.id
    end

    test "add_message/4 inserts assistant message with sources", %{session: session} do
      sources = [%{"provider" => "hubspot", "id" => "123", "name" => "Jane"}]
      assert {:ok, %Message{} = msg} =
               Chat.add_message(session, "assistant", "Answer", [], sources)
      assert msg.role == "assistant"
      assert msg.content == "Answer"
      assert Message.sources_list(msg) == [%{"provider" => "hubspot", "contact_id" => "123", "contact_name" => "Jane"}]
    end

    test "add_message/4 accepts atom keys in sources", %{session: session} do
      sources = [%{provider: "salesforce", id: "456", name: "John"}]
      assert {:ok, %Message{} = msg} =
               Chat.add_message(session, "assistant", "Done", [], sources)
      assert Message.sources_list(msg) == [%{"provider" => "salesforce", "contact_id" => "456", "contact_name" => "John"}]
    end
  end

  describe "connected_crm/1" do
    test "returns nil when no CRM" do
      user = user_fixture()
      assert Chat.connected_crm(user) == nil
    end

    test "returns :hubspot when user has HubSpot credential" do
      user = user_fixture()
      hubspot_credential_fixture(%{user_id: user.id})
      assert Chat.connected_crm(user) == :hubspot
    end

    test "returns :salesforce when user has Salesforce connection" do
      user = user_fixture()
      crm_connection_fixture(%{user_id: user.id, provider: "salesforce"})
      assert Chat.connected_crm(user) == :salesforce
    end
  end

  describe "search_contacts/2" do
    test "returns empty list for empty query" do
      user = user_fixture()
      assert Chat.search_contacts(user, "") == {:ok, []}
      assert Chat.search_contacts(user, "  ") == {:ok, []}
    end

    test "returns empty list when no CRM connected" do
      user = user_fixture()
      assert Chat.search_contacts(user, "john") == {:ok, []}
    end
  end

  describe "fetch_contact_data/2" do
    test "returns error for invalid contact shape" do
      user = user_fixture()
      assert Chat.fetch_contact_data(user, %{}) == {:error, :invalid_contact}
      assert Chat.fetch_contact_data(user, %{"id" => "1"}) == {:error, :invalid_contact}
    end
  end

  describe "ask_question/3" do
    setup do
      user = user_fixture()
      {:ok, session} = Chat.create_session(user)
      session = Chat.get_session!(user, session.id)
      %{user: user, session: session}
    end

    test "returns answer and sources when AI succeeds", %{user: user} do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_contact_question_answer, fn _q, _data, _opts ->
        {:ok, "Generated answer"}
      end)

      assert {:ok, %{answer: "Generated answer", sources: ["Jane"]}} =
               Chat.ask_question(user, "What is their email?", [%{"name" => "Jane", "id" => "1", "provider" => "hubspot"}])
    end

    test "returns error when AI fails", %{user: user} do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_contact_question_answer, fn _q, _data, _opts ->
        {:error, :service_unavailable}
      end)

      assert Chat.ask_question(user, "Question?", []) == {:error, :service_unavailable}
    end
  end

  describe "Chat.Message" do
    test "tagged_contacts_list/1 returns list from map" do
      msg = %Message{tagged_contacts: %{"contacts" => [%{"id" => "1"}]}}
      assert Message.tagged_contacts_list(msg) == [%{"id" => "1"}]
    end

    test "tagged_contacts_list/1 returns [] for nil" do
      assert Message.tagged_contacts_list(%Message{tagged_contacts: nil}) == []
    end

    test "sources_list/1 returns list from map" do
      msg = %Message{sources: %{"sources" => [%{"provider" => "hubspot"}]}}
      assert Message.sources_list(msg) == [%{"provider" => "hubspot"}]
    end

    test "sources_list/1 returns [] for nil" do
      assert Message.sources_list(%Message{sources: nil}) == []
    end

    test "changeset validates required fields" do
      changeset = Message.changeset(%Message{}, %{})
      refute changeset.valid?
      assert %{session_id: [_], role: [_], content: [_]} = errors_on(changeset)
    end

    test "changeset validates role inclusion" do
      session = insert_session_for_message()
      changeset =
        Message.changeset(%Message{}, %{session_id: session.id, role: "system", content: "x"})
      refute changeset.valid?
      assert %{role: [_]} = errors_on(changeset)
    end
  end

  describe "Chat.Session" do
    test "changeset requires user_id" do
      changeset = Session.changeset(%Session{}, %{})
      refute changeset.valid?
      assert %{user_id: [_]} = errors_on(changeset)
    end
  end

  defp insert_session_for_message do
    user = user_fixture()
    {:ok, s} = Chat.create_session(user)
    SocialScribe.Repo.get!(Session, s.id)
  end
end
