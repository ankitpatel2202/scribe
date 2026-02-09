defmodule SocialScribe.Chat.Message do
  @moduledoc "Schema for Ask Anything chat messages."
  use Ecto.Schema
  import Ecto.Changeset

  schema "crm_chat_messages" do
    field :role, :string
    field :content, :string
    field :tagged_contacts, :map
    field :sources, :map

    belongs_to :session, SocialScribe.Chat.Session

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:session_id, :role, :content, :tagged_contacts, :sources])
    |> put_tagged_contacts_default()
    |> put_sources_default()
    |> validate_required([:session_id, :role, :content])
    |> validate_inclusion(:role, ["user", "assistant"])
    |> foreign_key_constraint(:session_id)
  end

  defp put_tagged_contacts_default(changeset) do
    case get_field(changeset, :tagged_contacts) do
      nil -> put_change(changeset, :tagged_contacts, %{})
      _ -> changeset
    end
  end

  defp put_sources_default(changeset) do
    case get_field(changeset, :sources) do
      nil -> put_change(changeset, :sources, %{})
      _ -> changeset
    end
  end

  def tagged_contacts_list(%__MODULE__{tagged_contacts: nil}), do: []
  def tagged_contacts_list(%__MODULE__{tagged_contacts: tc}) when is_map(tc) do
    Map.get(tc, "contacts", Map.get(tc, :contacts, [])) |> List.wrap()
  end
  def tagged_contacts_list(_), do: []

  def sources_list(%__MODULE__{sources: nil}), do: []
  def sources_list(%__MODULE__{sources: s}) when is_map(s) do
    Map.get(s, "sources", Map.get(s, :sources, [])) |> List.wrap()
  end
  def sources_list(_), do: []
end
