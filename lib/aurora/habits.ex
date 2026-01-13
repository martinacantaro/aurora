defmodule Aurora.Habits do
  @moduledoc """
  The Habits context for managing habits and tracking completions.
  """

  import Ecto.Query, warn: false
  alias Aurora.Repo
  alias Aurora.Habits.{Habit, HabitCompletion}

  # ============================================================================
  # Habits
  # ============================================================================

  def list_habits do
    Repo.all(Habit)
  end

  def list_habits_with_today_status do
    today = Date.utc_today()
    start_of_day = NaiveDateTime.new!(today, ~T[00:00:00])
    end_of_day = NaiveDateTime.new!(today, ~T[23:59:59])

    habits = Repo.all(Habit)

    Enum.map(habits, fn habit ->
      completed_today? =
        from(c in HabitCompletion,
          where: c.habit_id == ^habit.id,
          where: c.completed_at >= ^start_of_day and c.completed_at <= ^end_of_day
        )
        |> Repo.exists?()

      today_completion =
        from(c in HabitCompletion,
          where: c.habit_id == ^habit.id,
          where: c.completed_at >= ^start_of_day and c.completed_at <= ^end_of_day,
          limit: 1
        )
        |> Repo.one()

      %{
        habit: habit,
        completed_today: completed_today?,
        today_value: today_completion && today_completion.value,
        streak: calculate_streak(habit.id)
      }
    end)
  end

  def get_habit!(id) do
    Repo.get!(Habit, id)
  end

  def create_habit(attrs \\ %{}) do
    %Habit{}
    |> Habit.changeset(attrs)
    |> Repo.insert()
  end

  def update_habit(%Habit{} = habit, attrs) do
    habit
    |> Habit.changeset(attrs)
    |> Repo.update()
  end

  def delete_habit(%Habit{} = habit) do
    Repo.delete(habit)
  end

  def change_habit(%Habit{} = habit, attrs \\ %{}) do
    Habit.changeset(habit, attrs)
  end

  # ============================================================================
  # Completions
  # ============================================================================

  def complete_habit(habit_id, value \\ nil) do
    %HabitCompletion{}
    |> HabitCompletion.changeset(%{
      habit_id: habit_id,
      completed_at: NaiveDateTime.utc_now(),
      value: value
    })
    |> Repo.insert()
  end

  def uncomplete_habit_today(habit_id) do
    today = Date.utc_today()
    start_of_day = NaiveDateTime.new!(today, ~T[00:00:00])
    end_of_day = NaiveDateTime.new!(today, ~T[23:59:59])

    from(c in HabitCompletion,
      where: c.habit_id == ^habit_id,
      where: c.completed_at >= ^start_of_day and c.completed_at <= ^end_of_day
    )
    |> Repo.delete_all()
  end

  def toggle_habit_today(habit_id) do
    today = Date.utc_today()
    start_of_day = NaiveDateTime.new!(today, ~T[00:00:00])
    end_of_day = NaiveDateTime.new!(today, ~T[23:59:59])

    completed_today? =
      from(c in HabitCompletion,
        where: c.habit_id == ^habit_id,
        where: c.completed_at >= ^start_of_day and c.completed_at <= ^end_of_day
      )
      |> Repo.exists?()

    if completed_today? do
      uncomplete_habit_today(habit_id)
      {:ok, false}
    else
      case complete_habit(habit_id) do
        {:ok, _} -> {:ok, true}
        error -> error
      end
    end
  end

  def get_completions_for_date_range(habit_id, start_date, end_date) do
    start_dt = NaiveDateTime.new!(start_date, ~T[00:00:00])
    end_dt = NaiveDateTime.new!(end_date, ~T[23:59:59])

    from(c in HabitCompletion,
      where: c.habit_id == ^habit_id,
      where: c.completed_at >= ^start_dt and c.completed_at <= ^end_dt,
      order_by: [asc: c.completed_at]
    )
    |> Repo.all()
  end

  # ============================================================================
  # Analytics
  # ============================================================================

  defp calculate_streak(habit_id) do
    today = Date.utc_today()

    # Get all completion dates for this habit, ordered by date descending
    completion_dates =
      from(c in HabitCompletion,
        where: c.habit_id == ^habit_id,
        select: fragment("DATE(?)", c.completed_at),
        distinct: true,
        order_by: [desc: fragment("DATE(?)", c.completed_at)]
      )
      |> Repo.all()
      |> Enum.map(&parse_date/1)

    calculate_streak_from_dates(completion_dates, today, 0)
  end

  defp parse_date(%Date{} = date), do: date
  defp parse_date(date_string) when is_binary(date_string), do: Date.from_iso8601!(date_string)

  defp calculate_streak_from_dates([], _expected_date, streak), do: streak

  defp calculate_streak_from_dates([date | rest], expected_date, streak) do
    cond do
      Date.compare(date, expected_date) == :eq ->
        calculate_streak_from_dates(rest, Date.add(expected_date, -1), streak + 1)

      Date.compare(date, expected_date) == :lt and streak == 0 ->
        # Allow starting streak from yesterday if not completed today yet
        yesterday = Date.add(expected_date, -1)

        if Date.compare(date, yesterday) == :eq do
          calculate_streak_from_dates(rest, Date.add(yesterday, -1), 1)
        else
          0
        end

      true ->
        streak
    end
  end

  def get_completion_rate(habit_id, days \\ 30) do
    end_date = Date.utc_today()
    start_date = Date.add(end_date, -days)

    completions = get_completions_for_date_range(habit_id, start_date, end_date)
    unique_days = completions |> Enum.map(& &1.completed_at) |> Enum.uniq_by(&NaiveDateTime.to_date/1) |> length()

    (unique_days / days * 100) |> Float.round(1)
  end
end
