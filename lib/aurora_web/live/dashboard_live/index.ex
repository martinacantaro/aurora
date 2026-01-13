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

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:boards, boards)
     |> assign(:habits, habits_with_status)
     |> assign(:goals, goals)
     |> assign(:today_entry, today_entry)
     |> assign(:recent_entries, recent_entries)
     |> assign(:finance_summary, finance_summary)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="flex justify-between items-center mb-8">
        <h1 class="text-3xl font-bold">Aurora</h1>
        <.link href="/logout" method="delete" class="btn btn-ghost btn-sm">
          Sign Out
        </.link>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <!-- Boards Widget -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">
              <.icon name="hero-view-columns" class="w-5 h-5" />
              Boards
            </h2>
            <div class="space-y-2">
              <%= if Enum.empty?(@boards) do %>
                <p class="text-base-content/60">No boards yet</p>
              <% else %>
                <%= for board <- Enum.take(@boards, 5) do %>
                  <.link navigate={~p"/boards/#{board.id}"} class="block p-2 hover:bg-base-200 rounded">
                    <%= board.name %>
                  </.link>
                <% end %>
              <% end %>
            </div>
            <div class="card-actions justify-end mt-4">
              <.link navigate={~p"/boards"} class="btn btn-primary btn-sm">
                View All
              </.link>
            </div>
          </div>
        </div>

        <!-- Today's Habits Widget -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">
              <.icon name="hero-check-circle" class="w-5 h-5" />
              Today's Habits
            </h2>
            <div class="space-y-2">
              <%= if Enum.empty?(@habits) do %>
                <p class="text-base-content/60">No habits yet</p>
              <% else %>
                <%= for %{habit: habit, completed_today: completed?, streak: streak} <- Enum.take(@habits, 5) do %>
                  <div class="flex items-center justify-between p-2 hover:bg-base-200 rounded">
                    <div class="flex items-center gap-2">
                      <%= if completed? do %>
                        <.icon name="hero-check-circle-solid" class="w-5 h-5 text-success" />
                      <% else %>
                        <.icon name="hero-circle" class="w-5 h-5 text-base-content/40" />
                      <% end %>
                      <span class={if completed?, do: "line-through text-base-content/60", else: ""}>
                        <%= habit.name %>
                      </span>
                    </div>
                    <%= if streak > 0 do %>
                      <span class="badge badge-sm"><%= streak %> day streak</span>
                    <% end %>
                  </div>
                <% end %>
              <% end %>
            </div>
            <div class="card-actions justify-end mt-4">
              <.link navigate={~p"/habits"} class="btn btn-primary btn-sm">
                View All
              </.link>
            </div>
          </div>
        </div>

        <!-- Goals Widget -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">
              <.icon name="hero-flag" class="w-5 h-5" />
              Goals
            </h2>
            <div class="space-y-3">
              <%= if Enum.empty?(@goals) do %>
                <p class="text-base-content/60">No goals yet</p>
              <% else %>
                <%= for goal <- Enum.take(@goals, 4) do %>
                  <div class="flex items-center gap-3">
                    <div class="radial-progress text-primary text-xs" style={"--value:#{goal.progress}; --size:2.5rem; --thickness:3px;"}>
                      <%= goal.progress %>%
                    </div>
                    <div class="flex-1 min-w-0">
                      <p class="font-medium truncate"><%= goal.title %></p>
                      <p class="text-xs text-base-content/60"><%= Goals.timeframe_label(goal.timeframe) %></p>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
            <div class="card-actions justify-end mt-4">
              <.link navigate={~p"/goals"} class="btn btn-primary btn-sm">
                View All
              </.link>
            </div>
          </div>
        </div>

        <!-- Finance Widget -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">
              <.icon name="hero-banknotes" class="w-5 h-5" />
              Finance
              <span class="text-xs font-normal text-base-content/60">This Month</span>
            </h2>
            <div class="space-y-2">
              <div class="flex justify-between">
                <span class="text-sm">Income</span>
                <span class="text-success font-mono">+$<%= Decimal.round(@finance_summary.income, 2) %></span>
              </div>
              <div class="flex justify-between">
                <span class="text-sm">Expenses</span>
                <span class="text-error font-mono">-$<%= Decimal.round(@finance_summary.expenses, 2) %></span>
              </div>
              <div class="divider my-1"></div>
              <div class="flex justify-between font-semibold">
                <span>Balance</span>
                <span class={"font-mono #{if Decimal.compare(@finance_summary.balance, Decimal.new(0)) == :lt, do: "text-error", else: "text-success"}"}>
                  <%= if Decimal.compare(@finance_summary.balance, Decimal.new(0)) == :lt, do: "-" %>$<%= Decimal.round(Decimal.abs(@finance_summary.balance), 2) %>
                </span>
              </div>
            </div>
            <div class="card-actions justify-end mt-4">
              <.link navigate={~p"/finance"} class="btn btn-primary btn-sm">
                View All
              </.link>
            </div>
          </div>
        </div>

        <!-- Journal Widget -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">
              <.icon name="hero-book-open" class="w-5 h-5" />
              Journal
            </h2>
            <%= if @today_entry do %>
              <div class="space-y-2">
                <div class="flex items-center gap-2">
                  <%= if @today_entry.mood do %>
                    <span title={Journal.mood_label(@today_entry.mood)}><%= Journal.mood_emoji(@today_entry.mood) %></span>
                  <% end %>
                  <%= if @today_entry.energy do %>
                    <span title={Journal.energy_label(@today_entry.energy)}><%= Journal.energy_emoji(@today_entry.energy) %></span>
                  <% end %>
                  <span class="text-sm text-base-content/60">Today</span>
                </div>
                <%= if @today_entry.content do %>
                  <p class="text-sm line-clamp-3"><%= String.slice(@today_entry.content, 0, 150) %><%= if String.length(@today_entry.content || "") > 150, do: "..." %></p>
                <% end %>
              </div>
            <% else %>
              <p class="text-base-content/60">No entry for today yet</p>
            <% end %>
            <div class="card-actions justify-end mt-4">
              <.link navigate={~p"/journal"} class="btn btn-primary btn-sm">
                <%= if @today_entry, do: "View Journal", else: "Write Today" %>
              </.link>
            </div>
          </div>
        </div>

        <!-- Quick Stats Widget -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">
              <.icon name="hero-chart-bar" class="w-5 h-5" />
              Quick Stats
            </h2>
            <div class="stats stats-vertical shadow">
              <div class="stat">
                <div class="stat-title">Boards</div>
                <div class="stat-value text-primary"><%= length(@boards) %></div>
              </div>
              <div class="stat">
                <div class="stat-title">Habits Completed Today</div>
                <div class="stat-value text-success">
                  <%= Enum.count(@habits, & &1.completed_today) %>/<%= length(@habits) %>
                </div>
              </div>
              <div class="stat">
                <div class="stat-title">Active Goals</div>
                <div class="stat-value text-info"><%= length(@goals) %></div>
              </div>
              <div class="stat">
                <div class="stat-title">Journal Entries (7 days)</div>
                <div class="stat-value text-secondary"><%= length(@recent_entries) %></div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
