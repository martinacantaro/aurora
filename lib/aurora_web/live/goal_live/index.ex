defmodule AuroraWeb.GoalLive.Index do
  use AuroraWeb, :live_view

  alias Aurora.Goals
  alias Aurora.Goals.Goal

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Goals")
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
        action = if socket.assigns.editing_goal, do: "updated", else: "created"

        {:noreply,
         socket
         |> assign(:show_form, false)
         |> assign(:editing_goal, nil)
         |> assign(:parent_goal, nil)
         |> load_goals()
         |> put_flash(:info, "Goal #{action}!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save goal")}
    end
  end

  def handle_event("delete_goal", %{"id" => id}, socket) do
    goal = Goals.get_goal!(id)

    case Goals.delete_goal(goal) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_goals()
         |> put_flash(:info, "Goal deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete goal")}
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

  defp progress_color(progress) when progress >= 80, do: "progress-success"
  defp progress_color(progress) when progress >= 50, do: "progress-info"
  defp progress_color(progress) when progress >= 25, do: "progress-warning"
  defp progress_color(_), do: "progress-error"

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
          <h1 class="text-3xl font-bold">Goals</h1>
        </div>
        <button phx-click="show_form" class="btn btn-primary">
          <.icon name="hero-plus" class="w-4 h-4" />
          New Goal
        </button>
      </div>

      <!-- Timeframe Filter Tabs -->
      <div class="tabs tabs-boxed mb-6">
        <a
          phx-click="filter_timeframe"
          phx-value-timeframe="all"
          class={"tab #{if @selected_timeframe == "all", do: "tab-active"}"}
        >
          All
        </a>
        <%= for {label, value} <- Goals.timeframes() do %>
          <a
            phx-click="filter_timeframe"
            phx-value-timeframe={value}
            class={"tab #{if @selected_timeframe == value, do: "tab-active"}"}
          >
            <%= label %>
          </a>
        <% end %>
      </div>

      <!-- Goals by Timeframe -->
      <%= if Enum.empty?(@goals) do %>
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body text-center">
            <p class="text-base-content/60">No goals yet. Create your first goal to start tracking!</p>
          </div>
        </div>
      <% else %>
        <div class="space-y-8">
          <%= for {timeframe, goals} <- filter_grouped_goals(@grouped_goals, @selected_timeframe) do %>
            <div class="card bg-base-100 shadow-lg">
              <div class="card-body">
                <div class="flex justify-between items-center mb-4">
                  <h2 class="card-title text-xl">
                    <.icon name={timeframe_icon(timeframe)} class="w-5 h-5" />
                    <%= Goals.timeframe_label(timeframe) %> Goals
                    <span class="badge badge-neutral"><%= length(goals) %></span>
                  </h2>
                </div>

                <div class="space-y-4">
                  <%= for goal <- goals do %>
                    <.goal_card goal={goal} level={0} myself={@myself} />
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <!-- Goal Form Modal -->
      <%= if @show_form do %>
        <div class="modal modal-open">
          <div class="modal-box max-w-lg">
            <div class="flex justify-between items-center mb-4">
              <h3 class="font-bold text-lg">
                <%= if @editing_goal, do: "Edit Goal", else: "New Goal" %>
              </h3>
              <button phx-click="close_form" class="btn btn-ghost btn-sm btn-circle">
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            </div>

            <form phx-submit="save_goal" class="space-y-4">
              <!-- Title -->
              <div class="form-control">
                <label class="label"><span class="label-text font-semibold">Title</span></label>
                <input
                  type="text"
                  name="title"
                  value={if @editing_goal, do: @editing_goal.title, else: ""}
                  class="input input-bordered"
                  placeholder="What do you want to achieve?"
                  required
                />
              </div>

              <!-- Description -->
              <div class="form-control">
                <label class="label"><span class="label-text font-semibold">Description</span></label>
                <textarea
                  name="description"
                  class="textarea textarea-bordered h-20"
                  placeholder="Why is this goal important?"
                ><%= if @editing_goal, do: @editing_goal.description, else: "" %></textarea>
              </div>

              <!-- Timeframe & Category -->
              <div class="grid grid-cols-2 gap-4">
                <div class="form-control">
                  <label class="label"><span class="label-text font-semibold">Timeframe</span></label>
                  <select name="timeframe" class="select select-bordered">
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
                  <label class="label"><span class="label-text font-semibold">Category</span></label>
                  <select name="category" class="select select-bordered">
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
                <label class="label"><span class="label-text font-semibold">Parent Goal (optional)</span></label>
                <select name="parent_id" class="select select-bordered">
                  <option value="">None - Top Level Goal</option>
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
                  <span class="label-text font-semibold">Progress</span>
                  <span class="label-text-alt"><%= if @editing_goal, do: @editing_goal.progress, else: 0 %>%</span>
                </label>
                <input
                  type="range"
                  name="progress"
                  min="0"
                  max="100"
                  value={if @editing_goal, do: @editing_goal.progress, else: 0}
                  class="range range-primary"
                />
                <div class="w-full flex justify-between text-xs px-2 mt-1">
                  <span>0%</span>
                  <span>25%</span>
                  <span>50%</span>
                  <span>75%</span>
                  <span>100%</span>
                </div>
              </div>

              <!-- Actions -->
              <div class="modal-action">
                <%= if @editing_goal do %>
                  <button
                    type="button"
                    phx-click="delete_goal"
                    phx-value-id={@editing_goal.id}
                    data-confirm="Delete this goal and all its sub-goals?"
                    class="btn btn-error btn-outline mr-auto"
                  >
                    Delete
                  </button>
                <% end %>
                <button type="button" phx-click="close_form" class="btn btn-ghost">Cancel</button>
                <button type="submit" class="btn btn-primary">
                  <%= if @editing_goal, do: "Save", else: "Create" %>
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

  defp goal_card(assigns) do
    ~H"""
    <div class={"border-l-4 pl-4 #{if @level > 0, do: "ml-6 border-base-300", else: "border-primary"}"}>
      <div class="flex items-start gap-4">
        <!-- Progress Circle -->
        <div class="radial-progress text-primary" style={"--value:#{@goal.progress}; --size:3rem; --thickness:4px;"} role="progressbar">
          <span class="text-xs font-bold"><%= @goal.progress %>%</span>
        </div>

        <!-- Goal Content -->
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 flex-wrap">
            <h3 class="font-semibold text-lg"><%= @goal.title %></h3>
            <%= if @goal.category do %>
              <span class={"badge badge-sm #{Goals.category_color(@goal.category)} text-white"}>
                <%= Goals.category_label(@goal.category) %>
              </span>
            <% end %>
          </div>

          <%= if @goal.description do %>
            <p class="text-sm text-base-content/60 mt-1"><%= @goal.description %></p>
          <% end %>

          <!-- Progress Bar -->
          <div class="mt-2">
            <progress class={"progress w-full #{progress_color(@goal.progress)}"} value={@goal.progress} max="100"></progress>
          </div>
        </div>

        <!-- Actions -->
        <div class="flex gap-1">
          <button
            phx-click="show_form"
            phx-value-parent_id={@goal.id}
            class="btn btn-ghost btn-sm btn-square"
            title="Add sub-goal"
          >
            <.icon name="hero-plus" class="w-4 h-4" />
          </button>
          <button
            phx-click="edit_goal"
            phx-value-id={@goal.id}
            class="btn btn-ghost btn-sm btn-square"
            title="Edit"
          >
            <.icon name="hero-pencil" class="w-4 h-4" />
          </button>
        </div>
      </div>

      <!-- Children -->
      <%= if @goal.children && @goal.children != [] do %>
        <div class="mt-3 space-y-3">
          <%= for child <- @goal.children do %>
            <.goal_card goal={child} level={@level + 1} myself={@myself} />
          <% end %>
        </div>
      <% end %>
    </div>
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
