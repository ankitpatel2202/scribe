defmodule SocialScribe.Accounts.CrmConnection do
  @moduledoc """
  Schema for CRM OAuth connections (Salesforce, future CRMs).
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "crm_connections" do
    field :provider, :string
    field :uid, :string
    field :email, :string
    field :access_token, :string
    field :refresh_token, :string
    field :instance_url, :string
    field :expires_at, :utc_datetime

    belongs_to :user, SocialScribe.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(crm_connection, attrs) do
    crm_connection
    |> cast(attrs, [
      :provider,
      :uid,
      :email,
      :access_token,
      :refresh_token,
      :instance_url,
      :expires_at,
      :user_id
    ])
    |> validate_required([:provider, :access_token, :user_id])
    |> unique_constraint([:user_id, :provider])
    |> foreign_key_constraint(:user_id)
  end
end
