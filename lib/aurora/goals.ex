defmodule Aurora.Goals do
  @moduledoc """
  The Goals context for managing hierarchical goals across different timeframes.
  """

  import Ecto.Query, warn: false
  alias Aurora.Repo
  alias Aurora.Goals.Goal

  @doc """
  Lists all top-level goals (no parent) with their children preloaded.
  """
  def list_goals do
    Goal
    |> where([g], is_nil(g.parent_id))
    |> order_by([g], [asc: g.timeframe, asc: g.inserted_at])
    |> Repo.all()
    |> Repo.preload(children: children_query())
  end

  @doc """
  Lists goals by timeframe.
  """
  def list_goals_by_timeframe(timeframe) do
    Goal
    |> where([g], g.timeframe == ^timeframe)
    |> where([g], is_nil(g.parent_id))
    |> order_by([g], asc: g.inserted_at)
    |> Repo.all()
    |> Repo.preload(children: children_query())
  end

  @doc """
  Lists goals by category.
  """
  def list_goals_by_category(category) do
    Goal
    |> where([g], g.category == ^category)
    |> where([g], is_nil(g.parent_id))
    |> order_by([g], [asc: g.timeframe, asc: g.inserted_at])
    |> Repo.all()
    |> Repo.preload(children: children_query())
  end

  defp children_query do
    from(g in Goal, order_by: [asc: g.inserted_at], preload: [children: ^children_query_nested()])
  end

  defp children_query_nested do
    from(g in Goal, order_by: [asc: g.inserted_at])
  end

  @doc """
  Gets a single goal with children preloaded.
  """
  def get_goal!(id) do
    Goal
    |> Repo.get!(id)
    |> Repo.preload([:parent, children: children_query()])
  end

  @doc """
  Creates a goal.
  """
  def create_goal(attrs \\ %{}) do
    %Goal{}
    |> Goal.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a goal.
  """
  def update_goal(%Goal{} = goal, attrs) do
    goal
    |> Goal.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a goal and all its children.
  """
  def delete_goal(%Goal{} = goal) do
    Repo.delete(goal)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking goal changes.
  """
  def change_goal(%Goal{} = goal, attrs \\ %{}) do
    Goal.changeset(goal, attrs)
  end

  @doc """
  Updates the progress of a goal.
  """
  def update_progress(%Goal{} = goal, progress) when progress >= 0 and progress <= 100 do
    update_goal(goal, %{progress: progress})
  end

  @doc """
  Returns available timeframes.
  """
  def timeframes do
    [
      {"Daily", "daily"},
      {"Weekly", "weekly"},
      {"Monthly", "monthly"},
      {"Quarterly", "quarterly"},
      {"Yearly", "yearly"},
      {"Multi-Year", "multi_year"}
    ]
  end

  @doc """
  Returns available categories.
  """
  def categories do
    [
      {"Health", "health"},
      {"Career", "career"},
      {"Relationships", "relationships"},
      {"Finance", "finance"},
      {"Personal Growth", "personal_growth"},
      {"Other", "other"}
    ]
  end

  @doc """
  Returns the display name for a timeframe.
  """
  def timeframe_label(timeframe) do
    case timeframe do
      "daily" -> "Daily"
      "weekly" -> "Weekly"
      "monthly" -> "Monthly"
      "quarterly" -> "Quarterly"
      "yearly" -> "Yearly"
      "multi_year" -> "Multi-Year"
      _ -> timeframe
    end
  end

  @doc """
  Returns the display name for a category.
  """
  def category_label(category) do
    case category do
      "health" -> "Health"
      "career" -> "Career"
      "relationships" -> "Relationships"
      "finance" -> "Finance"
      "personal_growth" -> "Personal Growth"
      "other" -> "Other"
      nil -> "Uncategorized"
      _ -> category
    end
  end

  @doc """
  Returns a color class for a category.
  """
  def category_color(category) do
    case category do
      "health" -> "bg-success"
      "career" -> "bg-info"
      "relationships" -> "bg-secondary"
      "finance" -> "bg-warning"
      "personal_growth" -> "bg-primary"
      "other" -> "bg-neutral"
      _ -> "bg-base-300"
    end
  end

  @doc """
  Calculates aggregate progress from children goals.
  Returns the average progress of all children, or the goal's own progress if no children.
  """
  def calculate_aggregate_progress(%Goal{children: []} = goal), do: goal.progress
  def calculate_aggregate_progress(%Goal{children: children}) do
    total = Enum.reduce(children, 0, fn child, acc -> acc + child.progress end)
    div(total, length(children))
  end

  @doc """
  Gets goals that can be potential parents for a given goal.
  Excludes the goal itself and its descendants.
  """
  def get_potential_parents(nil), do: list_all_goals()
  def get_potential_parents(%Goal{id: id}) do
    descendant_ids = get_descendant_ids(id)
    excluded_ids = [id | descendant_ids]

    Goal
    |> where([g], g.id not in ^excluded_ids)
    |> order_by([g], [asc: g.timeframe, asc: g.title])
    |> Repo.all()
  end

  defp list_all_goals do
    Goal
    |> order_by([g], [asc: g.timeframe, asc: g.title])
    |> Repo.all()
  end

  defp get_descendant_ids(goal_id) do
    children = Repo.all(from(g in Goal, where: g.parent_id == ^goal_id, select: g.id))

    children ++ Enum.flat_map(children, &get_descendant_ids/1)
  end
end
