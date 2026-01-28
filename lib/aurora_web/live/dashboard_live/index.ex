defmodule AuroraWeb.DashboardLive.Index do
  use AuroraWeb, :live_view

  alias Aurora.Boards
  alias Aurora.Habits
  alias Aurora.Goals
  alias Aurora.Journal
  alias Aurora.Finance

  @impl true
  def mount(_params, _session, socket) do
    boards = Boards.list_boards()
    habits_with_status = Habits.list_habits_with_today_status()
    goals = Goals.list_goals()
    today_entry = Journal.get_entry_for_date(Date.utc_today())
    recent_entries = Journal.recent_entries(7)
    finance_summary = Finance.get_current_month_summary()
    recent_transactions = Finance.get_recent_transactions(3)

    # Calculate discipline score (habit completion rate)
    total_habits = length(habits_with_status)
    completed_habits = Enum.count(habits_with_status, & &1.completed_today)
    discipline_pct = if total_habits > 0, do: round(completed_habits / total_habits * 100), else: 0

    # Calculate best streak
    best_streak = habits_with_status
      |> Enum.map(& &1.streak)
      |> Enum.max(fn -> 0 end)

    {:ok,
     socket
     |> assign(:page_title, "Command Bridge")
     |> assign(:boards, boards)
     |> assign(:habits, habits_with_status)
     |> assign(:goals, goals)
     |> assign(:today_entry, today_entry)
     |> assign(:recent_entries, recent_entries)
     |> assign(:finance_summary, finance_summary)
     |> assign(:recent_transactions, recent_transactions)
     |> assign(:discipline_pct, discipline_pct)
     |> assign(:best_streak, best_streak)
     |> assign(:completed_habits, completed_habits)
     |> assign(:total_habits, total_habits)}
  end

  defp mood_to_vitality(nil), do: 50
  defp mood_to_vitality(mood), do: mood * 20

  defp energy_to_pct(nil), do: 50
  defp energy_to_pct(energy), do: energy * 20

  defp wealth_indicator(balance) do
    cond do
      Decimal.compare(balance, Decimal.new(1000)) == :gt -> 100
      Decimal.compare(balance, Decimal.new(500)) == :gt -> 80
      Decimal.compare(balance, Decimal.new(0)) == :gt -> 60
      Decimal.compare(balance, Decimal.new(-500)) == :gt -> 40
      true -> 20
    end
  end

  defp format_currency(amount) do
    amount |> Decimal.round(0) |> Decimal.to_string()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-300">
      <!-- Command Header -->
      <header class="border-b border-primary/30 bg-base-200">
        <div class="container mx-auto px-4 py-4">
          <div class="flex justify-between items-center">
            <div class="flex items-center gap-3">
              <div class="text-primary text-2xl">⚔</div>
              <h1 class="text-2xl tracking-wider text-primary glow-gold-text">Aurora Command</h1>
            </div>
            <.link href="/logout" method="delete" class="btn btn-ghost btn-sm text-base-content/60 hover:text-primary">
              <.icon name="hero-arrow-right-on-rectangle" class="w-5 h-5" />
            </.link>
          </div>
        </div>
      </header>

      <main class="container mx-auto px-4 py-6">
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">

          <!-- Left Column: Character Panel -->
          <div class="lg:col-span-3">
            <div class="card card-ornate corner-tl corner-tr corner-bl corner-br p-4 space-y-4">
              <h2 class="panel-header">Character Status</h2>

              <!-- Vitality (Mood) -->
              <div class="space-y-1">
                <div class="flex justify-between items-center">
                  <span class="stat-block-label">Vitality</span>
                  <span class="text-xs text-base-content/60">
                    <%= if @today_entry && @today_entry.mood do %>
                      <%= Journal.mood_label(@today_entry.mood) %>
                    <% else %>
                      Unknown
                    <% end %>
                  </span>
                </div>
                <div class="progress-rpg">
                  <div class="progress-rpg-fill fill-success" style={"width: #{mood_to_vitality(@today_entry && @today_entry.mood)}%"}></div>
                </div>
              </div>

              <!-- Energy -->
              <div class="space-y-1">
                <div class="flex justify-between items-center">
                  <span class="stat-block-label">Energy</span>
                  <span class="text-xs text-base-content/60">
                    <%= if @today_entry && @today_entry.energy do %>
                      <%= Journal.energy_label(@today_entry.energy) %>
                    <% else %>
                      Unknown
                    <% end %>
                  </span>
                </div>
                <div class="progress-rpg">
                  <div class="progress-rpg-fill fill-info" style={"width: #{energy_to_pct(@today_entry && @today_entry.energy)}%"}></div>
                </div>
              </div>

              <!-- Wealth -->
              <div class="space-y-1">
                <div class="flex justify-between items-center">
                  <span class="stat-block-label">Wealth</span>
                  <span class={"text-xs font-mono #{if Decimal.compare(@finance_summary.balance, Decimal.new(0)) == :lt, do: "text-error", else: "text-success"}"}>
                    <%= if Decimal.compare(@finance_summary.balance, Decimal.new(0)) == :lt, do: "-" %>$<%= format_currency(Decimal.abs(@finance_summary.balance)) %>
                  </span>
                </div>
                <div class="progress-rpg">
                  <div class="progress-rpg-fill" style={"width: #{wealth_indicator(@finance_summary.balance)}%"}></div>
                </div>
              </div>

              <div class="divider-ornate text-xs">◆</div>

              <!-- Discipline Score -->
              <div class="text-center space-y-2">
                <div class="stat-block-label">Discipline</div>
                <div class="text-4xl font-mono text-primary glow-gold-text"><%= @discipline_pct %>%</div>
                <div class="text-xs text-base-content/60">
                  <%= @completed_habits %>/<%= @total_habits %> rituals today
                </div>
                <%= if @best_streak > 0 do %>
                  <div class="badge-imperial inline-block">
                    <.icon name="hero-fire" class="w-3 h-3 inline" /> <%= @best_streak %> day streak
                  </div>
                <% end %>
              </div>

              <div class="divider-ornate text-xs">◆</div>

              <!-- Recent Activity Log -->
              <div>
                <div class="stat-block-label mb-2">Ship's Log</div>
                <div class="space-y-2 text-sm">
                  <%= if @today_entry do %>
                    <div class="flex items-center gap-2 text-base-content/80">
                      <.icon name="hero-book-open" class="w-4 h-4 text-primary/60" />
                      <span>Journaled today</span>
                    </div>
                  <% end %>
                  <%= for tx <- Enum.take(@recent_transactions, 2) do %>
                    <div class="flex items-center gap-2 text-base-content/80">
                      <.icon name="hero-banknotes" class="w-4 h-4 text-primary/60" />
                      <span class={"font-mono text-xs #{if tx.is_income, do: "text-success", else: "text-error"}"}>
                        <%= if tx.is_income, do: "+", else: "-" %>$<%= format_currency(tx.amount) %>
                      </span>
                      <span class="truncate text-xs text-base-content/60"><%= tx.description || tx.category %></span>
                    </div>
                  <% end %>
                  <%= if length(@boards) > 0 do %>
                    <div class="flex items-center gap-2 text-base-content/80">
                      <.icon name="hero-view-columns" class="w-4 h-4 text-primary/60" />
                      <span><%= length(@boards) %> active operations</span>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>

          <!-- Center Column: Main Content -->
          <div class="lg:col-span-6 space-y-6">

            <!-- Active Quests (Goals) -->
            <div class="card card-ornate corner-tl corner-tr corner-bl corner-br p-4">
              <div class="flex justify-between items-center mb-4">
                <h2 class="panel-header mb-0 border-0 pb-0">Active Quests</h2>
                <.link navigate={~p"/goals"} class="btn btn-imperial btn-sm">
                  View All
                </.link>
              </div>

              <%= if Enum.empty?(@goals) do %>
                <p class="text-base-content/50 text-center py-6 italic">No active quests. Begin your journey.</p>
              <% else %>
                <div class="space-y-3">
                  <%= for goal <- Enum.take(@goals, 4) do %>
                    <div class={"quest-item #{if goal.progress >= 100, do: "quest-item-complete", else: "quest-item-active"}"}>
                      <div class={"quest-diamond #{if goal.progress >= 100, do: "quest-diamond-filled text-success", else: "text-primary"}"}></div>
                      <div class="flex-1 min-w-0">
                        <div class="flex justify-between items-center gap-2">
                          <span class="font-medium truncate"><%= goal.title %></span>
                          <span class="font-mono text-sm text-primary"><%= goal.progress %>%</span>
                        </div>
                        <div class="progress-rpg h-2 mt-1">
                          <div class={"progress-rpg-fill #{if goal.progress >= 100, do: "fill-success"}"} style={"width: #{goal.progress}%"}></div>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

            <!-- Today's Rituals (Habits) -->
            <div class="card card-ornate corner-tl corner-tr corner-bl corner-br p-4">
              <div class="flex justify-between items-center mb-4">
                <h2 class="panel-header mb-0 border-0 pb-0">Today's Rituals</h2>
                <.link navigate={~p"/habits"} class="btn btn-imperial btn-sm">
                  View All
                </.link>
              </div>

              <%= if Enum.empty?(@habits) do %>
                <p class="text-base-content/50 text-center py-6 italic">No rituals established. Forge your discipline.</p>
              <% else %>
                <div class="space-y-2">
                  <%= for %{habit: habit, completed_today: completed?, streak: streak} <- Enum.take(@habits, 6) do %>
                    <div class={"quest-item #{if completed?, do: "quest-item-complete"}"}>
                      <div class={"ritual-check #{if completed?, do: "ritual-check-complete"}"}>
                        <%= if completed? do %>
                          <.icon name="hero-check" class="w-3 h-3" />
                        <% end %>
                      </div>
                      <div class="flex-1 flex justify-between items-center">
                        <span class={if completed?, do: "line-through text-base-content/50", else: ""}>
                          <%= habit.name %>
                        </span>
                        <%= if streak > 0 do %>
                          <span class="badge-imperial text-xs">
                            <.icon name="hero-fire" class="w-3 h-3 inline" /> <%= streak %>
                          </span>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

            <!-- Treasury Overview -->
            <div class="card card-ornate corner-tl corner-tr corner-bl corner-br p-4">
              <div class="flex justify-between items-center mb-4">
                <h2 class="panel-header mb-0 border-0 pb-0">Treasury</h2>
                <.link navigate={~p"/finance"} class="btn btn-imperial btn-sm">
                  View All
                </.link>
              </div>

              <div class="grid grid-cols-3 gap-4 mb-4">
                <div class="text-center">
                  <div class="stat-block-label">Income</div>
                  <div class="font-mono text-success text-lg">+$<%= format_currency(@finance_summary.income) %></div>
                </div>
                <div class="text-center">
                  <div class="stat-block-label">Outflow</div>
                  <div class="font-mono text-error text-lg">-$<%= format_currency(@finance_summary.expenses) %></div>
                </div>
                <div class="text-center">
                  <div class="stat-block-label">Balance</div>
                  <div class={"font-mono text-lg #{if Decimal.compare(@finance_summary.balance, Decimal.new(0)) == :lt, do: "text-error", else: "text-primary glow-gold-text"}"}>
                    <%= if Decimal.compare(@finance_summary.balance, Decimal.new(0)) == :lt, do: "-" %>$<%= format_currency(Decimal.abs(@finance_summary.balance)) %>
                  </div>
                </div>
              </div>

              <!-- Income vs Expense bars -->
              <div class="space-y-2">
                <div class="space-y-1">
                  <div class="flex justify-between text-xs">
                    <span class="stat-block-label">Income</span>
                  </div>
                  <div class="progress-rpg h-3">
                    <div class="progress-rpg-fill fill-success" style="width: 100%"></div>
                  </div>
                </div>
                <div class="space-y-1">
                  <div class="flex justify-between text-xs">
                    <span class="stat-block-label">Expenses</span>
                  </div>
                  <div class="progress-rpg h-3">
                    <% expense_pct = if Decimal.compare(@finance_summary.income, Decimal.new(0)) == :gt do
                      @finance_summary.expenses |> Decimal.div(@finance_summary.income) |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer() |> min(100)
                    else
                      0
                    end %>
                    <div class="progress-rpg-fill fill-error" style={"width: #{expense_pct}%"}></div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Right Column: Operations & Chronicle -->
          <div class="lg:col-span-3 space-y-6">

            <!-- Operations (Boards) -->
            <div class="card card-ornate corner-tl corner-tr corner-bl corner-br p-4">
              <div class="flex justify-between items-center mb-4">
                <h2 class="panel-header mb-0 border-0 pb-0">Operations</h2>
                <.link navigate={~p"/boards"} class="btn btn-imperial btn-sm">
                  View
                </.link>
              </div>

              <%= if Enum.empty?(@boards) do %>
                <p class="text-base-content/50 text-center py-4 italic text-sm">No operations in progress.</p>
              <% else %>
                <div class="space-y-2">
                  <%= for board <- Enum.take(@boards, 4) do %>
                    <.link navigate={~p"/boards/#{board.id}"} class="quest-item block">
                      <.icon name="hero-view-columns" class="w-4 h-4 text-primary/60" />
                      <span class="text-sm"><%= board.name %></span>
                    </.link>
                  <% end %>
                </div>
              <% end %>
            </div>

            <!-- Chronicle (Journal) -->
            <div class="card card-ornate corner-tl corner-tr corner-bl corner-br p-4">
              <div class="flex justify-between items-center mb-4">
                <h2 class="panel-header mb-0 border-0 pb-0">Chronicle</h2>
                <.link navigate={~p"/journal"} class="btn btn-imperial btn-sm">
                  <%= if @today_entry, do: "View", else: "Write" %>
                </.link>
              </div>

              <%= if @today_entry do %>
                <div class="space-y-3">
                  <%= if @today_entry.mood || @today_entry.energy do %>
                    <div class="flex gap-4 text-sm">
                      <%= if @today_entry.mood do %>
                        <span title={Journal.mood_label(@today_entry.mood)}><%= Journal.mood_emoji(@today_entry.mood) %> <%= Journal.mood_label(@today_entry.mood) %></span>
                      <% end %>
                      <%= if @today_entry.energy do %>
                        <span title={Journal.energy_label(@today_entry.energy)}><%= Journal.energy_emoji(@today_entry.energy) %> <%= Journal.energy_label(@today_entry.energy) %></span>
                      <% end %>
                    </div>
                  <% end %>
                  <%= if @today_entry.content do %>
                    <p class="text-sm text-base-content/70 line-clamp-4 italic">
                      "<%= String.slice(@today_entry.content, 0, 150) %><%= if String.length(@today_entry.content || "") > 150, do: "..." %>"
                    </p>
                  <% end %>
                </div>
              <% else %>
                <p class="text-base-content/50 text-center py-4 italic text-sm">No chronicle entry for today.</p>
              <% end %>

              <%= if length(@recent_entries) > 1 do %>
                <div class="divider-ornate text-xs my-3">◆</div>
                <div class="text-xs text-base-content/50">
                  <%= length(@recent_entries) %> entries in the past 7 days
                </div>
              <% end %>
            </div>

            <!-- Quick Stats -->
            <div class="card card-ornate corner-tl corner-tr corner-bl corner-br p-4">
              <h2 class="panel-header">Statistics</h2>
              <div class="space-y-3">
                <div class="flex justify-between items-center">
                  <span class="stat-block-label">Operations</span>
                  <span class="font-mono text-primary"><%= length(@boards) %></span>
                </div>
                <div class="flex justify-between items-center">
                  <span class="stat-block-label">Active Quests</span>
                  <span class="font-mono text-primary"><%= length(@goals) %></span>
                </div>
                <div class="flex justify-between items-center">
                  <span class="stat-block-label">Daily Rituals</span>
                  <span class="font-mono text-primary"><%= @total_habits %></span>
                </div>
                <div class="flex justify-between items-center">
                  <span class="stat-block-label">Chronicle Entries</span>
                  <span class="font-mono text-primary"><%= length(@recent_entries) %></span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </main>

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
        <.link navigate={~p"/calendar"} class="hud-nav-item">
          <.icon name="hero-calendar-days" class="hud-nav-icon" />
          <span class="hud-nav-label">Calendar</span>
        </.link>
        <.link navigate={~p"/finance"} class="hud-nav-item">
          <.icon name="hero-banknotes" class="hud-nav-icon" />
          <span class="hud-nav-label">Treasury</span>
        </.link>
        <.link navigate={~p"/assistant"} class="hud-nav-item">
          <.icon name="hero-sparkles" class="hud-nav-icon" />
          <span class="hud-nav-label">Aurora AI</span>
        </.link>
      </nav>

      <!-- Bottom padding for HUD nav -->
      <div class="h-20"></div>
    </div>
    """
  end
end
