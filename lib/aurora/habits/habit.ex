defmodule Aurora.Habits.Habit do
  use Ecto.Schema
  import Ecto.Changeset

  schema "habits" do
    field :name, :string
    field :description, :string
    field :schedule_type, :string, default: "daily"
    field :schedule_data, :map, default: %{}
    field :time_of_day, :string, default: "anytime"
    field :tracking_type, :string, default: "binary"
    field :target_value, :decimal

    has_many :completions, Aurora.Habits.HabitCompletion

    timestamps()
  end

  @schedule_types ~w(daily weekly specific_days every_n_days)
  @time_of_day_options ~w(morning afternoon evening anytime)
  @tracking_types ~w(binary quantified duration)

  def changeset(habit, attrs) do
    habit
    |> cast(attrs, [:name, :description, :schedule_type, :schedule_data, :time_of_day, :tracking_type, :target_value])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:schedule_type, @schedule_types)
    |> validate_inclusion(:time_of_day, @time_of_day_options)
    |> validate_inclusion(:tracking_type, @tracking_types)
  end
end
