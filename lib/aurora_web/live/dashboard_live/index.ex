defmodule AuroraWeb.DashboardLive.Index do
  use AuroraWeb, :live_view

  alias Aurora.Boards
  alias Aurora.Habits
  alias Aurora.Goals

  @impl true
  def mount(_params, _session, socket) do
    boards = Boards.list_boards()
    habits_with_status = Habits.list_habits_with_today_status()
    goals = Goals.list_goals()

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:boards, boards)
     |> assign(:habits, habits_with_status)
     |> assign(:goals, goals)}
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
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
