defmodule SocialScribe.Chat.Session do
  @moduledoc "Schema for Ask Anything chat sessions."
  use Ecto.Schema
  import Ecto.Changeset

  schema "crm_chat_sessions" do
    field :title, :string, default: "New chat"

    belongs_to :user, SocialScribe.Accounts.User
    has_many :messages, SocialScribe.Chat.Message

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [:title, :user_id])
    |> validate_required([:user_id])
    |> foreign_key_constraint(:user_id)
  end
end
