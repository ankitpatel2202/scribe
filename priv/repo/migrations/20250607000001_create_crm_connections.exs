defmodule SocialScribe.Repo.Migrations.CreateCrmConnections do
  use Ecto.Migration

  def change do
    create table(:crm_connections) do
      add :provider, :string, null: false
      add :uid, :string
      add :email, :string
      add :access_token, :text, null: false
      add :refresh_token, :text
      add :instance_url, :string
      add :expires_at, :utc_datetime
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:crm_connections, [:user_id])
    create unique_index(:crm_connections, [:user_id, :provider])
  end
end
