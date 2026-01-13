defmodule AuroraWeb.FinanceLive.Index do
  use AuroraWeb, :live_view

  alias Aurora.Finance

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()

    {:ok,
     socket
     |> assign(:page_title, "Treasury")
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
    <div class="min-h-screen bg-base-300">
      <!-- Header -->
      <header class="border-b border-primary/30 bg-base-200">
        <div class="container mx-auto px-4 py-4">
          <div class="flex justify-between items-center">
            <div class="flex items-center gap-4">
              <.link navigate={~p"/"} class="btn btn-ghost btn-sm text-primary">
                <.icon name="hero-arrow-left" class="w-4 h-4" />
              </.link>
              <div class="flex items-center gap-3">
                <.icon name="hero-banknotes" class="w-6 h-6 text-primary" />
                <h1 class="text-2xl tracking-wider text-primary">Treasury</h1>
              </div>
            </div>
            <button phx-click="show_form" class="btn btn-imperial-primary btn-sm">
              <.icon name="hero-plus" class="w-4 h-4" />
              Add Transaction
            </button>
          </div>
        </div>
      </header>

      <main class="container mx-auto px-4 py-6 pb-24">
        <!-- Month Navigation -->
        <div class="flex justify-center items-center gap-4 mb-8">
          <button phx-click="prev_month" class="btn btn-imperial btn-sm">
            <.icon name="hero-chevron-left" class="w-5 h-5" />
          </button>
          <h2 class="text-xl w-48 text-center text-primary"><%= format_month(@view_month) %></h2>
          <button phx-click="next_month" class="btn btn-imperial btn-sm">
            <.icon name="hero-chevron-right" class="w-5 h-5" />
          </button>
        </div>

        <!-- Summary Cards -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
          <div class="card card-ornate corner-tl corner-tr p-4 text-center">
            <div class="stat-block-label mb-2">Income</div>
            <div class="text-2xl font-mono text-success">+$<%= format_amount(@summary.income) %></div>
          </div>
          <div class="card card-ornate p-4 text-center">
            <div class="stat-block-label mb-2">Expenses</div>
            <div class="text-2xl font-mono text-error">-$<%= format_amount(@summary.expenses) %></div>
          </div>
          <div class="card card-ornate corner-bl corner-br p-4 text-center">
            <div class="stat-block-label mb-2">Balance</div>
            <div class={"text-2xl font-mono #{if Decimal.compare(@summary.balance, Decimal.new(0)) == :lt, do: "text-error", else: "text-primary glow-gold-text"}"}>
              <%= if Decimal.compare(@summary.balance, Decimal.new(0)) == :lt, do: "-" %>$<%= format_amount(Decimal.abs(@summary.balance)) %>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <!-- Transactions List -->
          <div class="lg:col-span-2 card card-ornate corner-tl corner-tr corner-bl corner-br p-4">
            <h2 class="panel-header">Transactions</h2>

            <%= if Enum.empty?(@transactions) do %>
              <p class="text-base-content/50 text-center py-8 italic">No transactions this month.</p>
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
                      <tr class="hover:bg-base-200/50">
                        <td class="text-sm font-mono"><%= format_date(transaction.transaction_date) %></td>
                        <td>
                          <%= transaction.description || "-" %>
                        </td>
                        <td>
                          <%= if transaction.category do %>
                            <span class="badge-imperial"><%= Finance.category_label(transaction.category) %></span>
                          <% end %>
                        </td>
                        <td class={"text-right font-mono #{if transaction.is_income, do: "text-success", else: "text-error"}"}>
                          <%= if transaction.is_income, do: "+", else: "-" %>$<%= format_amount(transaction.amount) %>
                        </td>
                        <td>
                          <button
                            phx-click="edit_transaction"
                            phx-value-id={transaction.id}
                            class="btn btn-ghost btn-xs text-primary"
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

          <!-- Expenses by Category -->
          <div class="card card-ornate corner-tl corner-tr corner-bl corner-br p-4">
            <h2 class="panel-header">Expenses by Category</h2>

            <%= if Enum.empty?(@by_category) do %>
              <p class="text-base-content/50 text-center py-8 italic">No expenses this month.</p>
            <% else %>
              <% total = total_expenses(@by_category) %>
              <div class="space-y-4">
                <%= for {category, amount} <- @by_category do %>
                  <div>
                    <div class="flex justify-between text-sm mb-1">
                      <span class="flex items-center gap-2">
                        <.icon name={Finance.category_icon(category)} class="w-4 h-4 text-primary" />
                        <%= Finance.category_label(category) %>
                      </span>
                      <span class="font-mono text-error">$<%= format_amount(amount) %></span>
                    </div>
                    <div class="progress-rpg h-3">
                      <div class="progress-rpg-fill fill-error" style={"width: #{category_percentage(amount, total)}%"}></div>
                    </div>
                    <div class="text-xs text-base-content/50 text-right mt-1">
                      <%= category_percentage(amount, total) %>%
                    </div>
                  </div>
                <% end %>
              </div>

              <div class="divider-ornate my-4 text-xs">◆</div>

              <div class="flex justify-between font-semibold">
                <span class="stat-block-label">Total Expenses</span>
                <span class="font-mono text-error">$<%= format_amount(total) %></span>
              </div>
            <% end %>
          </div>
        </div>
      </main>

      <!-- Transaction Form Modal -->
      <%= if @show_form do %>
        <div class="modal modal-open">
          <div class="modal-box card-ornate border border-primary/50">
            <div class="flex justify-between items-center mb-4">
              <h3 class="panel-header mb-0 pb-0 border-0">
                <%= if @editing_transaction, do: "Edit Transaction", else: "Add Transaction" %>
              </h3>
              <button phx-click="close_form" class="btn btn-ghost btn-sm text-primary">
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            </div>

            <form phx-submit="save_transaction" class="space-y-4">
              <!-- Type Toggle -->
              <div class="form-control">
                <label class="label">
                  <span class="stat-block-label">Type</span>
                </label>
                <div class="flex gap-2">
                  <label class={"btn flex-1 btn-imperial #{if !@editing_transaction || !@editing_transaction.is_income, do: "btn-imperial-danger"}"}>
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
                  <label class={"btn flex-1 btn-imperial #{if @editing_transaction && @editing_transaction.is_income, do: "!bg-success/20 !border-success !text-success"}"}>
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
                  <span class="stat-block-label">Amount</span>
                </label>
                <label class="input input-imperial flex items-center gap-2">
                  <span class="text-primary">$</span>
                  <input
                    type="number"
                    name="amount"
                    step="0.01"
                    min="0"
                    value={if @editing_transaction, do: format_amount(@editing_transaction.amount), else: ""}
                    class="grow bg-transparent focus:outline-none"
                    placeholder="0.00"
                    required
                  />
                </label>
              </div>

              <!-- Description -->
              <div class="form-control">
                <label class="label">
                  <span class="stat-block-label">Description</span>
                </label>
                <input
                  type="text"
                  name="description"
                  value={if @editing_transaction, do: @editing_transaction.description, else: ""}
                  class="input input-imperial"
                  placeholder="What was this for?"
                />
              </div>

              <!-- Category -->
              <div class="form-control">
                <label class="label">
                  <span class="stat-block-label">Category</span>
                </label>
                <select name="category" class="select input-imperial">
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
                  <span class="stat-block-label">Date</span>
                </label>
                <input
                  type="date"
                  name="transaction_date"
                  value={if @editing_transaction, do: @editing_transaction.transaction_date, else: Date.utc_today()}
                  class="input input-imperial"
                  required
                />
              </div>

              <!-- Actions -->
              <div class="flex justify-between pt-4">
                <%= if @editing_transaction do %>
                  <button
                    type="button"
                    phx-click="delete_transaction"
                    phx-value-id={@editing_transaction.id}
                    data-confirm="Delete this transaction?"
                    class="btn btn-imperial-danger"
                  >
                    Delete
                  </button>
                <% else %>
                  <div></div>
                <% end %>
                <div class="flex gap-2">
                  <button type="button" phx-click="close_form" class="btn btn-imperial">Cancel</button>
                  <button type="submit" class="btn btn-imperial-primary">
                    <%= if @editing_transaction, do: "Save", else: "Add" %>
                  </button>
                </div>
              </div>
            </form>
          </div>
          <div class="modal-backdrop bg-base-300/80" phx-click="close_form"></div>
        </div>
      <% end %>

      <!-- HUD Navigation -->
      <nav class="fixed bottom-0 left-0 right-0 hud-nav">
        <.link navigate={~p"/boards"} class="hud-nav-item">
          <.icon name="hero-view-columns" class="hud-nav-icon" />
          <span class="hud-nav-label">Operations</span>
        </.link>
        <.link navigate={~p"/goals"} class="hud-nav-item">
          <.icon name="hero-flag" class="hud-nav-icon" />
          <span class="hud-nav-label">Quests</span>
        </.link>
        <.link navigate={~p"/habits"} class="hud-nav-item">
          <.icon name="hero-bolt" class="hud-nav-icon" />
          <span class="hud-nav-label">Rituals</span>
        </.link>
        <.link navigate={~p"/journal"} class="hud-nav-item">
          <.icon name="hero-book-open" class="hud-nav-icon" />
          <span class="hud-nav-label">Chronicle</span>
        </.link>
        <.link navigate={~p"/finance"} class="hud-nav-item hud-nav-item-active">
          <.icon name="hero-banknotes" class="hud-nav-icon" />
          <span class="hud-nav-label">Treasury</span>
        </.link>
      </nav>
    </div>
    """
  end
end
