defmodule Aurora.Habits.HabitCompletion do
  use Ecto.Schema
  import Ecto.Changeset

  schema "habit_completions" do
    field :completed_at, :naive_datetime
    field :value, :decimal

    belongs_to :habit, Aurora.Habits.Habit

    timestamps()
  end

  def changeset(completion, attrs) do
    completion
    |> cast(attrs, [:completed_at, :value, :habit_id])
    |> validate_required([:completed_at, :habit_id])
    |> foreign_key_constraint(:habit_id)
  end
end
