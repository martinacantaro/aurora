defmodule Aurora.Boards.Label do
  use Ecto.Schema
  import Ecto.Changeset

  schema "labels" do
    field :name, :string
    field :color, :string, default: "#3b82f6"

    many_to_many :tasks, Aurora.Boards.Task, join_through: "task_labels"

    timestamps()
  end

  def changeset(label, attrs) do
    label
    |> cast(attrs, [:name, :color])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 50)
    |> validate_format(:color, ~r/^#[0-9a-fA-F]{6}$/, message: "must be a valid hex color")
  end
end
