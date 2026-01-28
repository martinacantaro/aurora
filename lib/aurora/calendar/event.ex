defmodule Aurora.Calendar.Event do
  use Ecto.Schema
  import Ecto.Changeset

  alias Aurora.Boards.Task
  alias Aurora.Goals.Goal

  @frequencies ~w(daily weekly monthly yearly)

  schema "calendar_events" do
    field :title, :string
    field :description, :string
    field :start_at, :utc_datetime
    field :end_at, :utc_datetime
    field :all_day, :boolean, default: false
    field :location, :string
    field :color, :string, default: "#3b82f6"

    # Recurrence
    field :is_recurring, :boolean, default: false
    field :recurrence_rule, :map

    # Self-referential for recurring event instances
    belongs_to :parent_event, __MODULE__
    has_many :instances, __MODULE__, foreign_key: :parent_event_id

    # Links to other entities
    belongs_to :task, Task
    belongs_to :goal, Goal

    timestamps()
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :title,
      :description,
      :start_at,
      :end_at,
      :all_day,
      :location,
      :color,
      :is_recurring,
      :recurrence_rule,
      :parent_event_id,
      :task_id,
      :goal_id
    ])
    |> validate_required([:title, :start_at])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_color()
    |> validate_recurrence_rule()
    |> validate_end_after_start()
    |> foreign_key_constraint(:parent_event_id)
    |> foreign_key_constraint(:task_id)
    |> foreign_key_constraint(:goal_id)
  end

  defp validate_color(changeset) do
    validate_format(changeset, :color, ~r/^#[0-9A-Fa-f]{6}$/,
      message: "must be a valid hex color (e.g., #3b82f6)"
    )
  end

  defp validate_recurrence_rule(changeset) do
    case get_change(changeset, :recurrence_rule) do
      nil ->
        changeset

      rule when is_map(rule) ->
        if valid_recurrence_rule?(rule) do
          changeset
        else
          add_error(changeset, :recurrence_rule, "invalid recurrence rule format")
        end

      _ ->
        add_error(changeset, :recurrence_rule, "must be a map")
    end
  end

  defp valid_recurrence_rule?(rule) do
    frequency = Map.get(rule, "frequency") || Map.get(rule, :frequency)
    frequency in @frequencies
  end

  defp validate_end_after_start(changeset) do
    start_at = get_field(changeset, :start_at)
    end_at = get_field(changeset, :end_at)

    if start_at && end_at && DateTime.compare(end_at, start_at) == :lt do
      add_error(changeset, :end_at, "must be after start time")
    else
      changeset
    end
  end

  # Predefined colors for events
  def colors do
    [
      {"Blue", "#3b82f6"},
      {"Red", "#ef4444"},
      {"Green", "#22c55e"},
      {"Yellow", "#eab308"},
      {"Purple", "#a855f7"},
      {"Pink", "#ec4899"},
      {"Orange", "#f97316"},
      {"Teal", "#14b8a6"}
    ]
  end

  def frequencies, do: @frequencies
end
