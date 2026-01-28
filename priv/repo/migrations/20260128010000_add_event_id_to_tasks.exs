defmodule Aurora.Repo.Migrations.AddEventIdToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :event_id, references(:calendar_events, on_delete: :nilify_all)
    end

    create index(:tasks, [:event_id])
  end
end
