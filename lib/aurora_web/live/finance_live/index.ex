defmodule AuroraWeb.FinanceLive.Index do
  use AuroraWeb, :live_view

  alias Aurora.Finance

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()

    {:ok,
     socket
     |> assign(:page_title, "Finance")
     |> assign(:view_month, today)
     |> assign(:show_form, false)
     |> assign(:editing_transaction, nil)
     |> load_data()}
  end

  defp load_data(socket) do
    %{year: year, month: month} = socket.assigns.view_month
    transactions = Finance.list_transactions_for_month(year, month)
    summary = Finance.get_summary_for_month(year, month)
    by_category = Finance.get_expenses_by_category(year, month)

    socket
    |> assign(:transactions, transactions)
    |> assign(:summary, summary)
    |> assign(:by_category, by_category)
  end

  @impl true
  def handle_event("prev_month", _params, socket) do
    new_month = socket.assigns.view_month |> Date.beginning_of_month() |> Date.add(-1)
    {:noreply, socket |> assign(:view_month, new_month) |> load_data()}
  end

  def handle_event("next_month", _params, socket) do
    new_month = socket.assigns.view_month |> Date.end_of_month() |> Date.add(1)
    {:noreply, socket |> assign(:view_month, new_month) |> load_data()}
  end

  def handle_event("show_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_transaction, nil)}
  end

  def handle_event("edit_transaction", %{"id" => id}, socket) do
    transaction = Finance.get_transaction!(id)
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_transaction, transaction)}
  end

  def handle_event("close_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign(:editing_transaction, nil)}
  end

  def handle_event("save_transaction", params, socket) do
    transaction_params = %{
      amount: params["amount"],
      description: params["description"],
      category: if(params["category"] == "", do: nil, else: params["category"]),
      transaction_date: params["transaction_date"],
      is_income: params["is_income"] == "true"
    }

    result =
      if socket.assigns.editing_transaction do
        Finance.update_transaction(socket.assigns.editing_transaction, transaction_params)
      else
        Finance.create_transaction(transaction_params)
      end

    case result do
      {:ok, _transaction} ->
        action = if socket.assigns.editing_transaction, do: "updated", else: "added"
        {:noreply,
         socket
         |> assign(:show_form, false)
         |> assign(:editing_transaction, nil)
         |> load_data()
         |> put_flash(:info, "Transaction #{action}!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save transaction")}
    end
  end

  def handle_event("delete_transaction", %{"id" => id}, socket) do
    transaction = Finance.get_transaction!(id)

    case Finance.delete_transaction(transaction) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:show_form, false)
         |> assign(:editing_transaction, nil)
         |> load_data()
         |> put_flash(:info, "Transaction deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete transaction")}
    end
  end

  defp format_month(date) do
    Calendar.strftime(date, "%B %Y")
  end

  defp format_date(date) do
    Calendar.strftime(date, "%b %d")
  end

  defp format_amount(amount) do
    amount
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp total_expenses(by_category) do
    by_category
    |> Enum.reduce(Decimal.new(0), fn {_, amount}, acc -> Decimal.add(acc, amount) end)
  end

  defp category_percentage(amount, total) do
    if Decimal.compare(total, Decimal.new(0)) == :gt do
      amount
      |> Decimal.div(total)
      |> Decimal.mult(100)
      |> Decimal.round(1)
      |> Decimal.to_string()
    else
      "0"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <!-- Header -->
      <div class="flex justify-between items-center mb-8">
        <div class="flex items-center gap-4">
          <.link navigate={~p"/"} class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="w-4 h-4" />
          </.link>
          <h1 class="text-3xl font-bold">Finance</h1>
        </div>
        <button phx-click="show_form" class="btn btn-primary">
          <.icon name="hero-plus" class="w-4 h-4" />
          Add Transaction
        </button>
      </div>

      <!-- Month Navigation -->
      <div class="flex justify-center items-center gap-4 mb-8">
        <button phx-click="prev_month" class="btn btn-ghost btn-sm">
          <.icon name="hero-chevron-left" class="w-5 h-5" />
        </button>
        <h2 class="text-xl font-semibold w-48 text-center"><%= format_month(@view_month) %></h2>
        <button phx-click="next_month" class="btn btn-ghost btn-sm">
          <.icon name="hero-chevron-right" class="w-5 h-5" />
        </button>
      </div>

      <!-- Summary Cards -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
        <div class="stat bg-base-100 shadow rounded-box">
          <div class="stat-title">Income</div>
          <div class="stat-value text-success">$<%= format_amount(@summary.income) %></div>
        </div>
        <div class="stat bg-base-100 shadow rounded-box">
          <div class="stat-title">Expenses</div>
          <div class="stat-value text-error">$<%= format_amount(@summary.expenses) %></div>
        </div>
        <div class="stat bg-base-100 shadow rounded-box">
          <div class="stat-title">Balance</div>
          <div class={"stat-value #{if Decimal.compare(@summary.balance, Decimal.new(0)) == :lt, do: "text-error", else: "text-success"}"}>
            <%= if Decimal.compare(@summary.balance, Decimal.new(0)) == :lt, do: "-" %>$<%= format_amount(Decimal.abs(@summary.balance)) %>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Transactions List -->
        <div class="lg:col-span-2 card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title mb-4">Transactions</h2>

            <%= if Enum.empty?(@transactions) do %>
              <p class="text-base-content/60 text-center py-8">No transactions this month.</p>
            <% else %>
              <div class="overflow-x-auto">
                <table class="table">
                  <thead>
                    <tr>
                      <th>Date</th>
                      <th>Description</th>
                      <th>Category</th>
                      <th class="text-right">Amount</th>
                      <th></th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for transaction <- @transactions do %>
                      <tr class="hover">
                        <td class="text-sm"><%= format_date(transaction.transaction_date) %></td>
                        <td>
                          <%= transaction.description || "-" %>
                        </td>
                        <td>
                          <%= if transaction.category do %>
                            <span class="badge badge-sm"><%= Finance.category_label(transaction.category) %></span>
                          <% end %>
                        </td>
                        <td class={"text-right font-mono #{if transaction.is_income, do: "text-success", else: "text-error"}"}>
                          <%= if transaction.is_income, do: "+", else: "-" %>$<%= format_amount(transaction.amount) %>
                        </td>
                        <td>
                          <button
                            phx-click="edit_transaction"
                            phx-value-id={transaction.id}
                            class="btn btn-ghost btn-xs"
                          >
                            <.icon name="hero-pencil" class="w-3 h-3" />
                          </button>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Expenses by Category -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title mb-4">Expenses by Category</h2>

            <%= if Enum.empty?(@by_category) do %>
              <p class="text-base-content/60 text-center py-8">No expenses this month.</p>
            <% else %>
              <% total = total_expenses(@by_category) %>
              <div class="space-y-3">
                <%= for {category, amount} <- @by_category do %>
                  <div>
                    <div class="flex justify-between text-sm mb-1">
                      <span class="flex items-center gap-2">
                        <.icon name={Finance.category_icon(category)} class="w-4 h-4" />
                        <%= Finance.category_label(category) %>
                      </span>
                      <span class="font-mono">$<%= format_amount(amount) %></span>
                    </div>
                    <progress
                      class={"progress #{Finance.category_color(category)}"}
                      value={category_percentage(amount, total)}
                      max="100"
                    ></progress>
                    <div class="text-xs text-base-content/60 text-right">
                      <%= category_percentage(amount, total) %>%
                    </div>
                  </div>
                <% end %>
              </div>

              <div class="divider"></div>

              <div class="flex justify-between font-semibold">
                <span>Total Expenses</span>
                <span class="font-mono">$<%= format_amount(total) %></span>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Transaction Form Modal -->
      <%= if @show_form do %>
        <div class="modal modal-open">
          <div class="modal-box">
            <div class="flex justify-between items-center mb-4">
              <h3 class="font-bold text-lg">
                <%= if @editing_transaction, do: "Edit Transaction", else: "Add Transaction" %>
              </h3>
              <button phx-click="close_form" class="btn btn-ghost btn-sm btn-circle">
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            </div>

            <form phx-submit="save_transaction" class="space-y-4">
              <!-- Type Toggle -->
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">Type</span>
                </label>
                <div class="flex gap-2">
                  <label class={"btn flex-1 #{if !@editing_transaction || !@editing_transaction.is_income, do: "btn-error", else: ""}"}>
                    <input
                      type="radio"
                      name="is_income"
                      value="false"
                      checked={!@editing_transaction || !@editing_transaction.is_income}
                      class="hidden"
                    />
                    <.icon name="hero-arrow-trending-down" class="w-4 h-4" />
                    Expense
                  </label>
                  <label class={"btn flex-1 #{if @editing_transaction && @editing_transaction.is_income, do: "btn-success", else: ""}"}>
                    <input
                      type="radio"
                      name="is_income"
                      value="true"
                      checked={@editing_transaction && @editing_transaction.is_income}
                      class="hidden"
                    />
                    <.icon name="hero-arrow-trending-up" class="w-4 h-4" />
                    Income
                  </label>
                </div>
              </div>

              <!-- Amount -->
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">Amount</span>
                </label>
                <label class="input input-bordered flex items-center gap-2">
                  <span>$</span>
                  <input
                    type="number"
                    name="amount"
                    step="0.01"
                    min="0"
                    value={if @editing_transaction, do: format_amount(@editing_transaction.amount), else: ""}
                    class="grow"
                    placeholder="0.00"
                    required
                  />
                </label>
              </div>

              <!-- Description -->
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">Description</span>
                </label>
                <input
                  type="text"
                  name="description"
                  value={if @editing_transaction, do: @editing_transaction.description, else: ""}
                  class="input input-bordered"
                  placeholder="What was this for?"
                />
              </div>

              <!-- Category -->
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">Category</span>
                </label>
                <select name="category" class="select select-bordered">
                  <option value="">Select category</option>
                  <%= for cat <- Finance.categories() do %>
                    <option
                      value={cat}
                      selected={@editing_transaction && @editing_transaction.category == cat}
                    >
                      <%= Finance.category_label(cat) %>
                    </option>
                  <% end %>
                </select>
              </div>

              <!-- Date -->
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-semibold">Date</span>
                </label>
                <input
                  type="date"
                  name="transaction_date"
                  value={if @editing_transaction, do: @editing_transaction.transaction_date, else: Date.utc_today()}
                  class="input input-bordered"
                  required
                />
              </div>

              <!-- Actions -->
              <div class="modal-action">
                <%= if @editing_transaction do %>
                  <button
                    type="button"
                    phx-click="delete_transaction"
                    phx-value-id={@editing_transaction.id}
                    data-confirm="Delete this transaction?"
                    class="btn btn-error btn-outline mr-auto"
                  >
                    Delete
                  </button>
                <% end %>
                <button type="button" phx-click="close_form" class="btn btn-ghost">Cancel</button>
                <button type="submit" class="btn btn-primary">
                  <%= if @editing_transaction, do: "Save", else: "Add" %>
                </button>
              </div>
            </form>
          </div>
          <div class="modal-backdrop" phx-click="close_form"></div>
        </div>
      <% end %>
    </div>
    """
  end
end
