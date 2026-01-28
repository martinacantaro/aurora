defmodule Aurora.Assistant.ToolCall do
  use Ecto.Schema
  import Ecto.Changeset

  alias Aurora.Assistant.Message

  @statuses ~w(pending running success error cancelled)

  schema "assistant_tool_calls" do
    field :tool_use_id, :string
    field :tool_name, :string
    field :tool_input, :map
    field :tool_output, :map
    field :status, :string, default: "pending"
    field :error_message, :string
    field :requires_confirmation, :boolean, default: false
    field :confirmed_at, :utc_datetime

    belongs_to :message, Message

    timestamps()
  end

  @doc false
  def changeset(tool_call, attrs) do
    tool_call
    |> cast(attrs, [
      :tool_use_id,
      :tool_name,
      :tool_input,
      :tool_output,
      :status,
      :error_message,
      :requires_confirmation,
      :confirmed_at,
      :message_id
    ])
    |> validate_required([:tool_name, :message_id])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:message_id)
  end

  def statuses, do: @statuses
end
