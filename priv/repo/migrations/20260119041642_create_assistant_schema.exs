defmodule Aurora.Repo.Migrations.CreateAssistantSchema do
  use Ecto.Migration

  def change do
    # Conversations table
    create table(:assistant_conversations) do
      add :title, :string
      add :archived, :boolean, default: false

      timestamps()
    end

    # Messages table
    create table(:assistant_messages) do
      add :role, :string, null: false
      add :content, :text
      add :conversation_id, references(:assistant_conversations, on_delete: :delete_all), null: false
      add :completed, :boolean, default: true
      add :input_tokens, :integer
      add :output_tokens, :integer

      timestamps()
    end

    create index(:assistant_messages, [:conversation_id])
    create index(:assistant_messages, [:inserted_at])

    # Tool calls audit log
    create table(:assistant_tool_calls) do
      add :message_id, references(:assistant_messages, on_delete: :delete_all), null: false
      add :tool_use_id, :string
      add :tool_name, :string, null: false
      add :tool_input, :map
      add :tool_output, :map
      add :status, :string, default: "pending"
      add :error_message, :text
      add :requires_confirmation, :boolean, default: false
      add :confirmed_at, :utc_datetime

      timestamps()
    end

    create index(:assistant_tool_calls, [:message_id])
    create index(:assistant_tool_calls, [:tool_name])
    create index(:assistant_tool_calls, [:status])
  end
end
