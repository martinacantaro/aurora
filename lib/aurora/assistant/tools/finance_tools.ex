defmodule Aurora.Assistant.Tools.FinanceTools do
  @moduledoc """
  Tool definitions and executors for financial transactions.
  """

  alias Aurora.Finance

  def definitions do
    [
      %{
        name: "list_transactions",
        description: "List recent transactions or transactions for a specific month",
        input_schema: %{
          type: "object",
          properties: %{
            year: %{type: "integer", description: "Year to filter by"},
            month: %{type: "integer", description: "Month to filter by (1-12)"},
            limit: %{type: "integer", description: "Number of recent transactions to return"}
          },
          required: []
        }
      },
      %{
        name: "get_finance_summary",
        description: "Get financial summary (income, expenses, balance) for current month or specified period",
        input_schema: %{
          type: "object",
          properties: %{
            year: %{type: "integer", description: "Year"},
            month: %{type: "integer", description: "Month (1-12)"}
          },
          required: []
        }
      },
      %{
        name: "create_transaction",
        description: "Record a new income or expense transaction",
        input_schema: %{
          type: "object",
          properties: %{
            amount: %{type: "number", description: "Transaction amount (positive number)"},
            is_income: %{type: "boolean", description: "True for income, false for expense"},
            description: %{type: "string", description: "Description of the transaction"},
            category: %{
              type: "string",
              description: "Category of the transaction",
              enum: ["housing", "food", "transportation", "utilities", "healthcare",
                     "entertainment", "education", "shopping", "savings", "debt", "other"]
            },
            date: %{type: "string", format: "date", description: "Transaction date (default: today)"}
          },
          required: ["amount"]
        }
      },
      %{
        name: "update_transaction",
        description: "Update an existing transaction",
        input_schema: %{
          type: "object",
          properties: %{
            transaction_id: %{type: "integer", description: "The transaction to update"},
            amount: %{type: "number", description: "New amount"},
            description: %{type: "string", description: "New description"},
            category: %{type: "string", description: "New category"}
          },
          required: ["transaction_id"]
        }
      },
      %{
        name: "delete_transaction",
        description: "Delete a transaction. This action requires confirmation.",
        input_schema: %{
          type: "object",
          properties: %{
            transaction_id: %{type: "integer", description: "The transaction to delete"}
          },
          required: ["transaction_id"]
        }
      }
    ]
  end

  def execute("list_transactions", args) do
    transactions = cond do
      args["year"] && args["month"] ->
        Finance.list_transactions_for_month(args["year"], args["month"])
      args["limit"] ->
        Finance.get_recent_transactions(args["limit"])
      true ->
        Finance.get_recent_transactions(10)
    end
    {:ok, format_transactions(transactions)}
  end

  def execute("get_finance_summary", args) do
    summary = if args["year"] && args["month"] do
      Finance.get_summary_for_month(args["year"], args["month"])
    else
      Finance.get_current_month_summary()
    end
    {:ok, format_summary(summary)}
  end

  def execute("create_transaction", args) do
    date = case args["date"] do
      nil -> Date.utc_today()
      date_str ->
        case Date.from_iso8601(date_str) do
          {:ok, d} -> d
          _ -> Date.utc_today()
        end
    end

    attrs = %{
      amount: Decimal.new("#{args["amount"]}"),
      is_income: args["is_income"] || false,
      description: args["description"],
      category: args["category"],
      transaction_date: date
    }

    case Finance.create_transaction(attrs) do
      {:ok, txn} ->
        type = if txn.is_income, do: "income", else: "expense"
        {:ok, %{
          id: txn.id,
          message: "Recorded #{type} of $#{txn.amount}"
        }}
      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  def execute("update_transaction", %{"transaction_id" => id} = args) do
    try do
      txn = Finance.get_transaction!(id)
      attrs = args
        |> Map.drop(["transaction_id"])
        |> Enum.reduce(%{}, fn
          {"amount", v}, acc -> Map.put(acc, :amount, Decimal.new("#{v}"))
          {k, v}, acc -> Map.put(acc, String.to_existing_atom(k), v)
        end)

      case Finance.update_transaction(txn, attrs) do
        {:ok, txn} ->
          {:ok, %{id: txn.id, message: "Transaction updated"}}
        {:error, changeset} ->
          {:error, format_errors(changeset)}
      end
    rescue
      Ecto.NoResultsError -> {:error, "Transaction not found with ID #{id}"}
    end
  end

  def execute("delete_transaction", %{"transaction_id" => id}) do
    try do
      txn = Finance.get_transaction!(id)
      case Finance.delete_transaction(txn) do
        {:ok, _} ->
          {:ok, %{message: "Transaction deleted"}}
        {:error, _} ->
          {:error, "Failed to delete transaction"}
      end
    rescue
      Ecto.NoResultsError -> {:error, "Transaction not found with ID #{id}"}
    end
  end

  defp format_transactions(transactions) do
    %{
      count: length(transactions),
      transactions: Enum.map(transactions, fn t ->
        %{
          id: t.id,
          amount: Decimal.to_string(t.amount),
          is_income: t.is_income,
          type: if(t.is_income, do: "income", else: "expense"),
          description: t.description,
          category: t.category,
          category_label: if(t.category, do: Finance.category_label(t.category)),
          date: t.transaction_date
        }
      end)
    }
  end

  defp format_summary(summary) do
    %{
      income: Decimal.to_string(Decimal.round(summary.income, 2)),
      expenses: Decimal.to_string(Decimal.round(summary.expenses, 2)),
      balance: Decimal.to_string(Decimal.round(summary.balance, 2)),
      transaction_count: summary.transaction_count
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end
end
