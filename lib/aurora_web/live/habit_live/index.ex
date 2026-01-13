defmodule AuroraWeb.HabitLive.Index do
  use AuroraWeb, :live_view

  alias Aurora.Habits

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Daily Rituals")
     |> assign(:editing_habit, nil)
     |> assign(:show_new_form, false)
     |> load_habits()}
  end

  defp load_habits(socket) do
    assign(socket, :habits, Habits.list_habits_with_today_status())
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    habit_id = String.to_integer(id)

    case Habits.toggle_habit_today(habit_id) do
      {:ok, _completed} ->
        {:noreply, load_habits(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to toggle ritual")}
    end
  end

  def handle_event("show_new", _params, socket) do
    {:noreply, assign(socket, :show_new_form, true)}
  end

  def handle_event("cancel_new", _params, socket) do
    {:noreply, assign(socket, :show_new_form, false)}
  end

  def handle_event("create", %{"habit" => habit_params}, socket) do
    case Habits.create_habit(habit_params) do
      {:ok, _habit} ->
        {:noreply,
         socket
         |> assign(:show_new_form, false)
         |> load_habits()
         |> put_flash(:info, "Ritual established!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create ritual")}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_habit, String.to_integer(id))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_habit, nil)}
  end

  def handle_event("update", %{"habit" => habit_params} = params, socket) do
    id = params["value"]["id"] || params["id"]
    habit = Habits.get_habit!(id)

    case Habits.update_habit(habit, habit_params) do
      {:ok, _habit} ->
        {:noreply,
         socket
         |> assign(:editing_habit, nil)
         |> load_habits()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update ritual")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    habit = Habits.get_habit!(id)

    case Habits.delete_habit(habit) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_habits()
         |> put_flash(:info, "Ritual removed")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete ritual")}
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
                <.icon name="hero-bolt" class="w-6 h-6 text-primary" />
                <h1 class="text-2xl tracking-wider text-primary">Daily Rituals</h1>
              </div>
            </div>
            <button phx-click="show_new" class="btn btn-imperial-primary btn-sm">
              <.icon name="hero-plus" class="w-4 h-4" />
              New Ritual
            </button>
          </div>
        </div>
      </header>

      <main class="container mx-auto px-4 py-6 pb-24">
        <!-- New Ritual Form -->
        <%= if @show_new_form do %>
          <div class="card card-ornate corner-tl corner-tr corner-bl corner-br mb-6 p-4">
            <h2 class="panel-header">Establish New Ritual</h2>
            <form phx-submit="create" class="space-y-4">
              <div class="form-control">
                <label class="label"><span class="stat-block-label">Name</span></label>
                <input type="text" name="habit[name]" class="input input-imperial" required autofocus />
              </div>
              <div class="form-control">
                <label class="label"><span class="stat-block-label">Description (optional)</span></label>
                <textarea name="habit[description]" class="textarea input-imperial" rows="2"></textarea>
              </div>
              <div class="grid grid-cols-2 gap-4">
                <div class="form-control">
                  <label class="label"><span class="stat-block-label">Schedule</span></label>
                  <select name="habit[schedule_type]" class="select input-imperial">
                    <option value="daily">Daily</option>
                    <option value="weekly">Weekly</option>
                    <option value="specific_days">Specific Days</option>
                  </select>
                </div>
                <div class="form-control">
                  <label class="label"><span class="stat-block-label">Time of Day</span></label>
                  <select name="habit[time_of_day]" class="select input-imperial">
                    <option value="anytime">Anytime</option>
                    <option value="morning">Morning</option>
                    <option value="afternoon">Afternoon</option>
                    <option value="evening">Evening</option>
                  </select>
                </div>
              </div>
              <div class="flex gap-2 justify-end">
                <button type="button" phx-click="cancel_new" class="btn btn-imperial">Cancel</button>
                <button type="submit" class="btn btn-imperial-primary">Establish Ritual</button>
              </div>
            </form>
          </div>
        <% end %>

        <!-- Habits List -->
        <div class="space-y-4">
          <%= if Enum.empty?(@habits) do %>
            <div class="card card-ornate corner-tl corner-tr corner-bl corner-br p-8 text-center">
              <p class="text-base-content/50 italic">No rituals established. Begin forging your discipline.</p>
            </div>
          <% else %>
            <%= for %{habit: habit, completed_today: completed?, streak: streak} <- @habits do %>
              <div class={"card card-ornate p-4 #{if completed?, do: "border-success/30"}"}>
                <%= if @editing_habit == habit.id do %>
                  <form phx-submit="update" phx-value-id={habit.id} class="space-y-4">
                    <div class="form-control">
                      <input type="text" name="habit[name]" value={habit.name} class="input input-imperial" required autofocus />
                    </div>
                    <div class="form-control">
                      <textarea name="habit[description]" class="textarea input-imperial" rows="2"><%= habit.description %></textarea>
                    </div>
                    <div class="flex gap-2 justify-end">
                      <button type="button" phx-click="cancel_edit" class="btn btn-imperial btn-sm">Cancel</button>
                      <button type="submit" class="btn btn-imperial-primary btn-sm">Save</button>
                    </div>
                  </form>
                <% else %>
                  <div class="flex items-center gap-4">
                    <!-- Checkbox -->
                    <button
                      phx-click="toggle"
                      phx-value-id={habit.id}
                      class={"ritual-check w-12 h-12 #{if completed?, do: "ritual-check-complete"}"}
                    >
                      <%= if completed? do %>
                        <.icon name="hero-check" class="w-6 h-6" />
                      <% end %>
                    </button>

                    <!-- Habit Info -->
                    <div class="flex-1">
                      <h3 class={"text-lg font-semibold #{if completed?, do: "line-through text-base-content/50"}"}><%= habit.name %></h3>
                      <%= if habit.description do %>
                        <p class="text-sm text-base-content/60"><%= habit.description %></p>
                      <% end %>
                      <div class="flex gap-4 mt-1 text-xs text-base-content/50">
                        <span>
                          <.icon name="hero-clock" class="w-3 h-3 inline text-primary/60" />
                          <%= String.capitalize(habit.time_of_day) %>
                        </span>
                        <span>
                          <.icon name="hero-calendar" class="w-3 h-3 inline text-primary/60" />
                          <%= String.capitalize(habit.schedule_type) %>
                        </span>
                      </div>
                    </div>

                    <!-- Streak Badge -->
                    <%= if streak > 0 do %>
                      <div class="badge-imperial flex items-center gap-1 px-3 py-2">
                        <.icon name="hero-fire" class="w-4 h-4" />
                        <%= streak %> day<%= if streak > 1, do: "s" %>
                      </div>
                    <% end %>

                    <!-- Actions -->
                    <div class="dropdown dropdown-end">
                      <label tabindex="0" class="btn btn-ghost btn-sm text-primary">
                        <.icon name="hero-ellipsis-vertical" class="w-4 h-4" />
                      </label>
                      <ul tabindex="0" class="dropdown-content z-50 menu p-2 shadow bg-base-200 border border-primary/30 rounded w-40">
                        <li><a phx-click="edit" phx-value-id={habit.id} class="text-base-content hover:text-primary">Edit</a></li>
                        <li>
                          <a phx-click="delete" phx-value-id={habit.id} data-confirm="Abandon this ritual?" class="text-error hover:bg-error/20">
                            Delete
                          </a>
                        </li>
                      </ul>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          <% end %>
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
        <.link navigate={~p"/habits"} class="hud-nav-item hud-nav-item-active">
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
end
