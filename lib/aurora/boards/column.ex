defmodule Aurora.Boards.Column do
  use Ecto.Schema
  import Ecto.Changeset

  schema "columns" do
    field :name, :string
    field :position, :integer, default: 0

    belongs_to :board, Aurora.Boards.Board
    has_many :tasks, Aurora.Boards.Task, preload_order: [asc: :position]

    timestamps()
  end

  def changeset(column, attrs) do
    column
    |> cast(attrs, [:name, :position, :board_id])
    |> validate_required([:name, :board_id])
    |> validate_length(:name, min: 1, max: 100)
    |> foreign_key_constraint(:board_id)
  end
end
