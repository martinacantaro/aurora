defmodule Aurora.Repo.Migrations.CreateCalendarEvents do
  use Ecto.Migration

  def change do
    create table(:calendar_events) do
      add :title, :string, null: false
      add :description, :text
      add :start_at, :utc_datetime, null: false
      add :end_at, :utc_datetime
      add :all_day, :boolean, default: false
      add :location, :string
      add :color, :string, default: "#3b82f6"

      # Recurrence support
      add :is_recurring, :boolean, default: false
      add :recurrence_rule, :map  # {frequency, interval, until, count, days_of_week}
      add :parent_event_id, references(:calendar_events, on_delete: :delete_all)

      # Optional links to other entities
      add :task_id, references(:tasks, on_delete: :nilify_all)
      add :goal_id, references(:goals, on_delete: :nilify_all)

      timestamps()
    end

    create index(:calendar_events, [:start_at])
    create index(:calendar_events, [:end_at])
    create index(:calendar_events, [:parent_event_id])
    create index(:calendar_events, [:task_id])
    create index(:calendar_events, [:goal_id])
  end
end
