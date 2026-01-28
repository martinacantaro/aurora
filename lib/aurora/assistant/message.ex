defmodule Aurora.Assistant.Message do
  use Ecto.Schema
  import Ecto.Changeset

  alias Aurora.Assistant.{Conversation, ToolCall}

  @roles ~w(user assistant system)

  schema "assistant_messages" do
    field :role, :string
    field :content, :string
    field :completed, :boolean, default: true
    field :input_tokens, :integer
    field :output_tokens, :integer

    belongs_to :conversation, Conversation
    has_many :tool_calls, ToolCall

    timestamps()
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :completed, :input_tokens, :output_tokens, :conversation_id])
    |> validate_required([:role, :conversation_id])
    |> validate_inclusion(:role, @roles)
    |> foreign_key_constraint(:conversation_id)
  end

  def roles, do: @roles
end
