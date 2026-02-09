defmodule SocialScribe.Repo.Migrations.AddSourcesToCrmChatMessages do
  use Ecto.Migration

  def change do
    alter table(:crm_chat_messages) do
      # Sources metadata for UI (e.g. provider logos). Store as map: %{"sources" => [%{"provider" => "hubspot", "contact_id" => "...", "contact_name" => "..."}, ...]}
      add :sources, :map
    end
  end
end
