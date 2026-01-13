defmodule Aurora.Goals.Goal do
  use Ecto.Schema
  import Ecto.Changeset

  schema "goals" do
    field :title, :string
    field :description, :string
    field :timeframe, :string, default: "monthly"
    field :category, :string
    field :progress, :integer, default: 0

    belongs_to :parent, __MODULE__, foreign_key: :parent_id
    has_many :children, __MODULE__, foreign_key: :parent_id

    timestamps()
  end

  @timeframes ~w(daily weekly monthly quarterly yearly multi_year)
  @categories ~w(health career relationships finance personal_growth other)

  def changeset(goal, attrs) do
    goal
    |> cast(attrs, [:title, :description, :timeframe, :category, :progress, :parent_id])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_inclusion(:timeframe, @timeframes)
    |> validate_inclusion(:category, @categories ++ [nil])
    |> validate_number(:progress, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:parent_id)
  end
end
