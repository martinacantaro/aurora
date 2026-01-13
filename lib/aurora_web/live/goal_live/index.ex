defmodule AuroraWeb.GoalLive.Index do
  use AuroraWeb, :live_view

  alias Aurora.Goals

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Quest Log")
     |> assign(:selected_timeframe, "all")
     |> assign(:selected_goal, nil)
     |> assign(:show_form, false)
     |> assign(:editing_goal, nil)
     |> assign(:parent_goal, nil)
     |> load_goals()}
  end

  defp load_goals(socket) do
    goals = Goals.list_goals()

    # Group goals by timeframe for display
    grouped_goals =
      goals
      |> Enum.group_by(& &1.timeframe)
      |> Enum.sort_by(fn {tf, _} -> timeframe_order(tf) end)

    assign(socket, goals: goals, grouped_goals: grouped_goals)
  end

  defp timeframe_order(timeframe) do
    case timeframe do
      "daily" -> 0
      "weekly" -> 1
      "monthly" -> 2
      "quarterly" -> 3
      "yearly" -> 4
      "multi_year" -> 5
      _ -> 6
    end
  end

  @impl true
  def handle_event("show_form", params, socket) do
    parent_id = params["parent_id"]
    parent_goal = if parent_id, do: Goals.get_goal!(parent_id), else: nil

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_goal, nil)
     |> assign(:parent_goal, parent_goal)}
  end

  def handle_event("edit_goal", %{"id" => id}, socket) do
    goal = Goals.get_goal!(id)

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_goal, goal)
     |> assign(:parent_goal, goal.parent)}
  end

  def handle_event("close_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign(:editing_goal, nil)
     |> assign(:parent_goal, nil)}
  end

  def handle_event("save_goal", params, socket) do
    goal_params = %{
      title: params["title"],
      description: params["description"],
      timeframe: params["timeframe"],
      category: if(params["category"] == "", do: nil, else: params["category"]),
      progress: String.to_integer(params["progress"] || "0"),
      parent_id: if(params["parent_id"] == "", do: nil, else: String.to_integer(params["parent_id"]))
    }

    result =
      if socket.assigns.editing_goal do
        Goals.update_goal(socket.assigns.editing_goal, goal_params)
      else
        Goals.create_goal(goal_params)
      end

    case result do
      {:ok, _goal} ->
        action = if socket.assigns.editing_goal, do: "updated", else: "accepted"

        {:noreply,
         socket
         |> assign(:show_form, false)
         |> assign(:editing_goal, nil)
         |> assign(:parent_goal, nil)
         |> load_goals()
         |> put_flash(:info, "Quest #{action}!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save quest")}
    end
  end

  def handle_event("delete_goal", %{"id" => id}, socket) do
    goal = Goals.get_goal!(id)

    case Goals.delete_goal(goal) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_goals()
         |> put_flash(:info, "Quest abandoned")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete quest")}
    end
  end

  def handle_event("update_progress", %{"id" => id, "progress" => progress}, socket) do
    goal = Goals.get_goal!(id)
    progress_val = String.to_integer(progress)

    case Goals.update_progress(goal, progress_val) do
      {:ok, _goal} ->
        {:noreply, load_goals(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update progress")}
    end
  end

  def handle_event("filter_timeframe", %{"timeframe" => timeframe}, socket) do
    {:noreply, assign(socket, :selected_timeframe, timeframe)}
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
                <.icon name="hero-flag" class="w-6 h-6 text-primary" />
                <h1 class="text-2xl tracking-wider text-primary">Quest Log</h1>
              </div>
            </div>
            <button phx-click="show_form" class="btn btn-imperial-primary btn-sm">
              <.icon name="hero-plus" class="w-4 h-4" />
              New Quest
            </button>
          </div>
        </div>
      </header>

      <main class="container mx-auto px-4 py-6 pb-24">
        <!-- Timeframe Filter Tabs -->
        <div class="flex flex-wrap gap-2 mb-6">
          <button
            phx-click="filter_timeframe"
            phx-value-timeframe="all"
            class={"btn btn-sm btn-imperial #{if @selected_timeframe == "all", do: "btn-imperial-primary"}"}
          >
            All
          </button>
          <%= for {label, value} <- Goals.timeframes() do %>
            <button
              phx-click="filter_timeframe"
              phx-value-timeframe={value}
              class={"btn btn-sm btn-imperial #{if @selected_timeframe == value, do: "btn-imperial-primary"}"}
            >
              <%= label %>
            </button>
          <% end %>
        </div>

        <!-- Goals by Timeframe -->
        <%= if Enum.empty?(@goals) do %>
          <div class="card card-ornate corner-tl corner-tr corner-bl corner-br p-8 text-center">
            <p class="text-base-content/50 italic">No quests in your log. Begin your journey by accepting a quest.</p>
          </div>
        <% else %>
          <div class="space-y-6">
            <%= for {timeframe, goals} <- filter_grouped_goals(@grouped_goals, @selected_timeframe) do %>
              <div class="card card-ornate corner-tl corner-tr corner-bl corner-br p-4">
                <div class="flex justify-between items-center mb-4">
                  <h2 class="panel-header mb-0 pb-0 border-0 flex items-center gap-2">
                    <.icon name={timeframe_icon(timeframe)} class="w-5 h-5" />
                    <%= Goals.timeframe_label(timeframe) %> Quests
                    <span class="badge-imperial ml-2"><%= length(goals) %></span>
                  </h2>
                </div>

                <div class="space-y-4">
                  <%= for goal <- goals do %>
                    <.goal_card goal={goal} level={0} />
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </main>

      <!-- Goal Form Modal -->
      <%= if @show_form do %>
        <div class="modal modal-open">
          <div class="modal-box card-ornate border border-primary/50 max-w-lg">
            <div class="flex justify-between items-center mb-4">
              <h3 class="panel-header mb-0 pb-0 border-0">
                <%= if @editing_goal, do: "Edit Quest", else: "Accept New Quest" %>
              </h3>
              <button phx-click="close_form" class="btn btn-ghost btn-sm text-primary">
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            </div>

            <form phx-submit="save_goal" class="space-y-4">
              <!-- Title -->
              <div class="form-control">
                <label class="label"><span class="stat-block-label">Quest Title</span></label>
                <input
                  type="text"
                  name="title"
                  value={if @editing_goal, do: @editing_goal.title, else: ""}
                  class="input input-imperial"
                  placeholder="What do you seek to achieve?"
                  required
                />
              </div>

              <!-- Description -->
              <div class="form-control">
                <label class="label"><span class="stat-block-label">Description</span></label>
                <textarea
                  name="description"
                  class="textarea input-imperial h-20"
                  placeholder="Why is this quest important?"
                ><%= if @editing_goal, do: @editing_goal.description, else: "" %></textarea>
              </div>

              <!-- Timeframe & Category -->
              <div class="grid grid-cols-2 gap-4">
                <div class="form-control">
                  <label class="label"><span class="stat-block-label">Timeframe</span></label>
                  <select name="timeframe" class="select input-imperial">
                    <%= for {label, value} <- Goals.timeframes() do %>
                      <option
                        value={value}
                        selected={(@editing_goal && @editing_goal.timeframe == value) || (!@editing_goal && value == "monthly")}
                      >
                        <%= label %>
                      </option>
                    <% end %>
                  </select>
                </div>

                <div class="form-control">
                  <label class="label"><span class="stat-block-label">Category</span></label>
                  <select name="category" class="select input-imperial">
                    <option value="">None</option>
                    <%= for {label, value} <- Goals.categories() do %>
                      <option
                        value={value}
                        selected={@editing_goal && @editing_goal.category == value}
                      >
                        <%= label %>
                      </option>
                    <% end %>
                  </select>
                </div>
              </div>

              <!-- Parent Goal -->
              <div class="form-control">
                <label class="label"><span class="stat-block-label">Parent Quest (optional)</span></label>
                <select name="parent_id" class="select input-imperial">
                  <option value="">None - Main Quest</option>
                  <%= for potential_parent <- Goals.get_potential_parents(@editing_goal) do %>
                    <option
                      value={potential_parent.id}
                      selected={(@parent_goal && @parent_goal.id == potential_parent.id) || (@editing_goal && @editing_goal.parent_id == potential_parent.id)}
                    >
                      [<%= Goals.timeframe_label(potential_parent.timeframe) %>] <%= potential_parent.title %>
                    </option>
                  <% end %>
                </select>
              </div>

              <!-- Progress -->
              <div class="form-control">
                <label class="label">
                  <span class="stat-block-label">Progress</span>
                  <span class="text-primary font-mono"><%= if @editing_goal, do: @editing_goal.progress, else: 0 %>%</span>
                </label>
                <div class="progress-rpg h-6 relative">
                  <div
                    class={"progress-rpg-fill #{if (@editing_goal && @editing_goal.progress >= 100) || false, do: "fill-success"}"}
                    style={"width: #{if @editing_goal, do: @editing_goal.progress, else: 0}%"}
                  ></div>
                </div>
                <input
                  type="range"
                  name="progress"
                  min="0"
                  max="100"
                  value={if @editing_goal, do: @editing_goal.progress, else: 0}
                  class="range range-primary range-sm mt-2"
                />
              </div>

              <!-- Actions -->
              <div class="flex justify-between pt-4">
                <%= if @editing_goal do %>
                  <button
                    type="button"
                    phx-click="delete_goal"
                    phx-value-id={@editing_goal.id}
                    data-confirm="Abandon this quest and all sub-quests?"
                    class="btn btn-imperial-danger"
                  >
                    Abandon
                  </button>
                <% else %>
                  <div></div>
                <% end %>
                <div class="flex gap-2">
                  <button type="button" phx-click="close_form" class="btn btn-imperial">Cancel</button>
                  <button type="submit" class="btn btn-imperial-primary">
                    <%= if @editing_goal, do: "Save", else: "Accept Quest" %>
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
        <.link navigate={~p"/goals"} class="hud-nav-item hud-nav-item-active">
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
        <.link navigate={~p"/finance"} class="hud-nav-item">
          <.icon name="hero-banknotes" class="hud-nav-icon" />
          <span class="hud-nav-label">Treasury</span>
        </.link>
      </nav>
    </div>
    """
  end

  defp goal_card(assigns) do
    ~H"""
    <div class={"quest-item #{if @goal.progress >= 100, do: "quest-item-complete", else: "quest-item-active"} #{if @level > 0, do: "ml-6"}"}>
      <!-- Quest Diamond -->
      <div class={"quest-diamond #{if @goal.progress >= 100, do: "quest-diamond-filled text-success", else: "text-primary"}"}></div>

      <!-- Goal Content -->
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2 flex-wrap">
          <h3 class="font-semibold"><%= @goal.title %></h3>
          <%= if @goal.category do %>
            <span class="badge-imperial text-xs">
              <%= Goals.category_label(@goal.category) %>
            </span>
          <% end %>
        </div>

        <%= if @goal.description do %>
          <p class="text-sm text-base-content/60 mt-1"><%= @goal.description %></p>
        <% end %>

        <!-- Progress Bar -->
        <div class="progress-rpg h-2 mt-2">
          <div
            class={"progress-rpg-fill #{if @goal.progress >= 100, do: "fill-success"}"}
            style={"width: #{@goal.progress}%"}
          ></div>
        </div>
      </div>

      <!-- Progress & Actions -->
      <div class="flex items-center gap-2">
        <span class="font-mono text-primary text-sm"><%= @goal.progress %>%</span>
        <button
          phx-click="show_form"
          phx-value-parent_id={@goal.id}
          class="btn btn-ghost btn-sm text-primary"
          title="Add sub-quest"
        >
          <.icon name="hero-plus" class="w-4 h-4" />
        </button>
        <button
          phx-click="edit_goal"
          phx-value-id={@goal.id}
          class="btn btn-ghost btn-sm text-primary"
          title="Edit"
        >
          <.icon name="hero-pencil" class="w-4 h-4" />
        </button>
      </div>
    </div>

    <!-- Children -->
    <%= if @goal.children && @goal.children != [] do %>
      <div class="space-y-2 mt-2">
        <%= for child <- @goal.children do %>
          <.goal_card goal={child} level={@level + 1} />
        <% end %>
      </div>
    <% end %>
    """
  end

  defp filter_grouped_goals(grouped_goals, "all"), do: grouped_goals
  defp filter_grouped_goals(grouped_goals, timeframe) do
    Enum.filter(grouped_goals, fn {tf, _} -> tf == timeframe end)
  end

  defp timeframe_icon("daily"), do: "hero-sun"
  defp timeframe_icon("weekly"), do: "hero-calendar"
  defp timeframe_icon("monthly"), do: "hero-calendar-days"
  defp timeframe_icon("quarterly"), do: "hero-chart-bar"
  defp timeframe_icon("yearly"), do: "hero-star"
  defp timeframe_icon("multi_year"), do: "hero-trophy"
  defp timeframe_icon(_), do: "hero-flag"
end
