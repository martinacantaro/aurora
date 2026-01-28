defmodule Aurora.Assistant.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Aurora.Assistant.Message

  schema "assistant_conversations" do
    field :title, :string
    field :archived, :boolean, default: false

    has_many :messages, Message

    timestamps()
  end

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :archived])
    |> validate_length(:title, max: 255)
  end
end
