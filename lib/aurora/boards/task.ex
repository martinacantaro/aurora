defmodule Aurora.Boards.Task do
  use Ecto.Schema
  import Ecto.Changeset

  alias Aurora.Calendar.Event

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :position, :integer, default: 0
    field :priority, :integer, default: 4
    field :due_date, :date
    field :completed, :boolean, default: false
    field :completed_at, :utc_datetime

    belongs_to :column, Aurora.Boards.Column
    belongs_to :event, Event
    many_to_many :labels, Aurora.Boards.Label, join_through: "task_labels", on_replace: :delete

    timestamps()
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :description, :position, :priority, :due_date, :column_id, :event_id, :completed, :completed_at])
    |> validate_required([:title, :column_id])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_inclusion(:priority, 1..4)
    |> foreign_key_constraint(:column_id)
    |> foreign_key_constraint(:event_id)
  end
end
