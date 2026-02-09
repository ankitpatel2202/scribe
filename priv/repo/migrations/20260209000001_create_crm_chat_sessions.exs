defmodule SocialScribe.Repo.Migrations.CreateCrmChatSessions do
  use Ecto.Migration

  def change do
    create table(:crm_chat_sessions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, default: "New chat"

      timestamps(type: :utc_datetime)
    end

    create index(:crm_chat_sessions, [:user_id])
    create index(:crm_chat_sessions, [:user_id, :inserted_at])

    create table(:crm_chat_messages) do
      add :session_id, references(:crm_chat_sessions, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :content, :text, null: false
      add :tagged_contacts, :map

      timestamps(type: :utc_datetime)
    end

    create index(:crm_chat_messages, [:session_id])
  end
end
