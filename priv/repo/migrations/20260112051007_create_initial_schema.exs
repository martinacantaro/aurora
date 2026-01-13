defmodule Aurora.Repo.Migrations.CreateInitialSchema do
  use Ecto.Migration

  def change do
    # Boards for Kanban
    create table(:boards) do
      add :name, :string, null: false
      add :position, :integer, default: 0

      timestamps()
    end

    # Columns within boards
    create table(:columns) do
      add :name, :string, null: false
      add :position, :integer, default: 0
      add :board_id, references(:boards, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:columns, [:board_id])

    # Labels for tasks
    create table(:labels) do
      add :name, :string, null: false
      add :color, :string, default: "#3b82f6"

      timestamps()
    end

    # Tasks within columns
    create table(:tasks) do
      add :title, :string, null: false
      add :description, :text
      add :position, :integer, default: 0
      add :priority, :integer, default: 4
      add :due_date, :date
      add :column_id, references(:columns, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:tasks, [:column_id])
    create index(:tasks, [:due_date])

    # Join table for tasks and labels
    create table(:task_labels, primary_key: false) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :label_id, references(:labels, on_delete: :delete_all), null: false
    end

    create unique_index(:task_labels, [:task_id, :label_id])

    # Habits
    create table(:habits) do
      add :name, :string, null: false
      add :description, :text
      add :schedule_type, :string, default: "daily"
      add :schedule_data, :map, default: %{}
      add :time_of_day, :string, default: "anytime"
      add :tracking_type, :string, default: "binary"
      add :target_value, :decimal

      timestamps()
    end

    # Habit completions
    create table(:habit_completions) do
      add :completed_at, :naive_datetime, null: false
      add :value, :decimal
      add :habit_id, references(:habits, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:habit_completions, [:habit_id])
    create index(:habit_completions, [:completed_at])

    # Goals with hierarchy
    create table(:goals) do
      add :title, :string, null: false
      add :description, :text
      add :timeframe, :string, default: "monthly"
      add :category, :string
      add :progress, :integer, default: 0
      add :parent_id, references(:goals, on_delete: :nilify_all)

      timestamps()
    end

    create index(:goals, [:parent_id])
    create index(:goals, [:timeframe])

    # Journal entries
    create table(:journal_entries) do
      add :content, :text
      add :mood, :integer
      add :energy, :integer
      add :entry_date, :date, null: false

      timestamps()
    end

    create unique_index(:journal_entries, [:entry_date])

    # Financial transactions
    create table(:transactions) do
      add :amount, :decimal, null: false
      add :category, :string
      add :description, :string
      add :transaction_date, :date, null: false
      add :is_income, :boolean, default: false

      timestamps()
    end

    create index(:transactions, [:transaction_date])
    create index(:transactions, [:category])
  end
end
