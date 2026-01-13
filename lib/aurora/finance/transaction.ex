defmodule Aurora.Finance.Transaction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "transactions" do
    field :amount, :decimal
    field :category, :string
    field :description, :string
    field :transaction_date, :date
    field :is_income, :boolean, default: false

    timestamps()
  end

  @categories ~w(housing food transportation utilities healthcare entertainment education shopping savings debt other)

  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [:amount, :category, :description, :transaction_date, :is_income])
    |> validate_required([:amount, :transaction_date])
    |> validate_number(:amount, greater_than: 0)
    |> validate_inclusion(:category, @categories ++ [nil])
  end
end
