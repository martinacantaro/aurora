defmodule Aurora.Finance do
  @moduledoc """
  The Finance context for managing transactions and financial analytics.
  """

  import Ecto.Query, warn: false
  alias Aurora.Repo
  alias Aurora.Finance.Transaction

  @categories ~w(housing food transportation utilities healthcare entertainment education shopping savings debt other)

  def categories, do: @categories

  def category_label(nil), do: "Uncategorized"
  def category_label(category), do: category |> String.replace("_", " ") |> String.capitalize()

  def category_icon("housing"), do: "hero-home"
  def category_icon("food"), do: "hero-cake"
  def category_icon("transportation"), do: "hero-truck"
  def category_icon("utilities"), do: "hero-bolt"
  def category_icon("healthcare"), do: "hero-heart"
  def category_icon("entertainment"), do: "hero-film"
  def category_icon("education"), do: "hero-academic-cap"
  def category_icon("shopping"), do: "hero-shopping-bag"
  def category_icon("savings"), do: "hero-banknotes"
  def category_icon("debt"), do: "hero-credit-card"
  def category_icon(_), do: "hero-currency-dollar"

  def category_color("housing"), do: "bg-blue-500"
  def category_color("food"), do: "bg-orange-500"
  def category_color("transportation"), do: "bg-purple-500"
  def category_color("utilities"), do: "bg-yellow-500"
  def category_color("healthcare"), do: "bg-red-500"
  def category_color("entertainment"), do: "bg-pink-500"
  def category_color("education"), do: "bg-indigo-500"
  def category_color("shopping"), do: "bg-teal-500"
  def category_color("savings"), do: "bg-green-500"
  def category_color("debt"), do: "bg-gray-500"
  def category_color(_), do: "bg-base-300"

  # ============================================================================
  # Transactions CRUD
  # ============================================================================

  def list_transactions do
    Transaction
    |> order_by(desc: :transaction_date, desc: :inserted_at)
    |> Repo.all()
  end

  def list_transactions_for_month(year, month) do
    start_date = Date.new!(year, month, 1)
    end_date = Date.end_of_month(start_date)

    Transaction
    |> where([t], t.transaction_date >= ^start_date and t.transaction_date <= ^end_date)
    |> order_by(desc: :transaction_date, desc: :inserted_at)
    |> Repo.all()
  end

  def list_transactions_for_range(start_date, end_date) do
    Transaction
    |> where([t], t.transaction_date >= ^start_date and t.transaction_date <= ^end_date)
    |> order_by(desc: :transaction_date, desc: :inserted_at)
    |> Repo.all()
  end

  def get_transaction!(id) do
    Repo.get!(Transaction, id)
  end

  def create_transaction(attrs \\ %{}) do
    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Repo.insert()
  end

  def update_transaction(%Transaction{} = transaction, attrs) do
    transaction
    |> Transaction.changeset(attrs)
    |> Repo.update()
  end

  def delete_transaction(%Transaction{} = transaction) do
    Repo.delete(transaction)
  end

  def change_transaction(%Transaction{} = transaction, attrs \\ %{}) do
    Transaction.changeset(transaction, attrs)
  end

  # ============================================================================
  # Analytics
  # ============================================================================

  def get_summary_for_month(year, month) do
    start_date = Date.new!(year, month, 1)
    end_date = Date.end_of_month(start_date)
    get_summary_for_range(start_date, end_date)
  end

  def get_summary_for_range(start_date, end_date) do
    transactions = list_transactions_for_range(start_date, end_date)

    income = transactions
      |> Enum.filter(& &1.is_income)
      |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, t.amount) end)

    expenses = transactions
      |> Enum.reject(& &1.is_income)
      |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, t.amount) end)

    %{
      income: income,
      expenses: expenses,
      balance: Decimal.sub(income, expenses),
      transaction_count: length(transactions)
    }
  end

  def get_expenses_by_category(year, month) do
    start_date = Date.new!(year, month, 1)
    end_date = Date.end_of_month(start_date)

    Transaction
    |> where([t], t.transaction_date >= ^start_date and t.transaction_date <= ^end_date)
    |> where([t], t.is_income == false)
    |> group_by([t], t.category)
    |> select([t], {t.category, sum(t.amount)})
    |> Repo.all()
    |> Enum.map(fn {cat, amount} -> {cat || "other", amount} end)
    |> Enum.sort_by(fn {_, amount} -> Decimal.to_float(amount) end, :desc)
  end

  def get_monthly_totals(year) do
    start_date = Date.new!(year, 1, 1)
    end_date = Date.new!(year, 12, 31)

    transactions = list_transactions_for_range(start_date, end_date)

    1..12
    |> Enum.map(fn month ->
      month_transactions = Enum.filter(transactions, fn t -> t.transaction_date.month == month end)

      income = month_transactions
        |> Enum.filter(& &1.is_income)
        |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, t.amount) end)

      expenses = month_transactions
        |> Enum.reject(& &1.is_income)
        |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, t.amount) end)

      %{month: month, income: income, expenses: expenses}
    end)
  end

  def get_recent_transactions(limit \\ 5) do
    Transaction
    |> order_by(desc: :transaction_date, desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_current_month_summary do
    today = Date.utc_today()
    get_summary_for_month(today.year, today.month)
  end
end
