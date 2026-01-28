defmodule Aurora.Assistant.Tools.AnalyticsTools do
  @moduledoc """
  Tool definitions and executors for cross-domain analytics.
  """

  alias Aurora.{Boards, Goals, Habits, Journal, Finance}
  alias Aurora.Calendar, as: Cal

  def definitions do
    [
      %{
        name: "analyze_productivity",
        description: "Analyze overall productivity including task completion, habit streaks, and goal progress",
        input_schema: %{
          type: "object",
          properties: %{
            days: %{type: "integer", description: "Number of days to analyze", default: 30}
          },
          required: []
        }
      },
      %{
        name: "analyze_finances",
        description: "Analyze financial data including spending by category and trends",
        input_schema: %{
          type: "object",
          properties: %{
            start_date: %{type: "string", format: "date", description: "Start date"},
            end_date: %{type: "string", format: "date", description: "End date"}
          },
          required: []
        }
      },
      %{
        name: "get_daily_summary",
        description: "Get a comprehensive summary of today's status across all areas",
        input_schema: %{
          type: "object",
          properties: %{},
          required: []
        }
      },
      %{
        name: "get_weekly_report",
        description: "Generate a weekly productivity report",
        input_schema: %{
          type: "object",
          properties: %{
            week_offset: %{
              type: "integer",
              description: "0 for current week, -1 for last week",
              default: 0
            }
          },
          required: []
        }
      }
    ]
  end

  def execute("analyze_productivity", args) do
    days = args["days"] || 30

    habits = Habits.list_habits_with_today_status()
    goals = Goals.list_goals()

    habit_stats = %{
      total: length(habits),
      completed_today: Enum.count(habits, & &1.completed_today),
      best_streak: habits |> Enum.map(& &1.streak) |> Enum.max(fn -> 0 end),
      completion_rates: Enum.map(habits, fn h ->
        %{
          name: h.habit.name,
          rate: Habits.get_completion_rate(h.habit.id, days)
        }
      end) |> Enum.sort_by(& &1.rate, :desc)
    }

    goal_stats = %{
      total: length(goals),
      completed: Enum.count(goals, & &1.progress >= 100),
      in_progress: Enum.count(goals, & &1.progress > 0 && &1.progress < 100),
      not_started: Enum.count(goals, & &1.progress == 0),
      average_progress: calculate_average(goals, & &1.progress)
    }

    {:ok, %{
      period_days: days,
      habits: habit_stats,
      goals: goal_stats,
      insights: generate_productivity_insights(habit_stats, goal_stats)
    }}
  end

  def execute("analyze_finances", args) do
    end_date = parse_date(args["end_date"]) || Date.utc_today()
    start_date = parse_date(args["start_date"]) || Date.add(end_date, -30)

    summary = Finance.get_summary_for_range(start_date, end_date)
    today = Date.utc_today()
    category_breakdown = Finance.get_expenses_by_category(today.year, today.month)

    total_expenses = Decimal.to_float(summary.expenses)

    category_analysis = Enum.map(category_breakdown, fn {cat, amount} ->
      amount_float = Decimal.to_float(amount)
      %{
        category: cat,
        category_label: Finance.category_label(cat),
        amount: Decimal.to_string(amount),
        percentage: if(total_expenses > 0, do: Float.round(amount_float / total_expenses * 100, 1), else: 0)
      }
    end)
    |> Enum.sort_by(& &1.percentage, :desc)

    {:ok, %{
      period: "#{start_date} to #{end_date}",
      summary: %{
        income: Decimal.to_string(Decimal.round(summary.income, 2)),
        expenses: Decimal.to_string(Decimal.round(summary.expenses, 2)),
        balance: Decimal.to_string(Decimal.round(summary.balance, 2)),
        savings_rate: calculate_savings_rate(summary.income, summary.expenses)
      },
      category_breakdown: category_analysis,
      insights: generate_finance_insights(summary, category_analysis)
    }}
  end

  def execute("get_daily_summary", _args) do
    today = Date.utc_today()

    habits = Habits.list_habits_with_today_status()
    journal_entry = Journal.get_entry_for_date(today)
    finance = Finance.get_current_month_summary()
    recent_txns = Finance.get_recent_transactions(3)
    today_events = Cal.list_today_events()
    upcoming_events = Cal.list_upcoming_events(3)

    {:ok, %{
      date: today,
      day_of_week: day_of_week(today),
      habits: %{
        completed: Enum.count(habits, & &1.completed_today),
        total: length(habits),
        pending: habits
          |> Enum.reject(& &1.completed_today)
          |> Enum.map(& &1.habit.name)
          |> Enum.take(5)
      },
      journal: if journal_entry do
        %{
          has_entry: true,
          mood: journal_entry.mood,
          mood_label: if(journal_entry.mood, do: Journal.mood_label(journal_entry.mood)),
          energy: journal_entry.energy,
          energy_label: if(journal_entry.energy, do: Journal.energy_label(journal_entry.energy)),
          has_content: journal_entry.content != nil
        }
      else
        %{has_entry: false}
      end,
      finance: %{
        monthly_income: Decimal.to_string(Decimal.round(finance.income, 2)),
        monthly_expenses: Decimal.to_string(Decimal.round(finance.expenses, 2)),
        monthly_balance: Decimal.to_string(Decimal.round(finance.balance, 2)),
        recent_transactions: Enum.map(recent_txns, fn t ->
          %{
            amount: Decimal.to_string(t.amount),
            type: if(t.is_income, do: "income", else: "expense"),
            description: t.description
          }
        end)
      },
      calendar: %{
        events_today: length(today_events),
        today_events: Enum.map(today_events, fn e ->
          %{title: e.title, time: format_time(e.start_at)}
        end),
        upcoming: Enum.map(upcoming_events, fn e ->
          %{title: e.title, date: DateTime.to_date(e.start_at)}
        end)
      }
    }}
  end

  def execute("get_weekly_report", args) do
    offset = args["week_offset"] || 0
    today = Date.utc_today()

    # Calculate week boundaries
    day_of_week = Date.day_of_week(today)
    monday = Date.add(today, -(day_of_week - 1) + (offset * 7))
    sunday = Date.add(monday, 6)

    # Get data for the week
    journal_entries = Journal.list_entries_for_range(monday, sunday)
    finance_summary = Finance.get_summary_for_range(monday, sunday)
    events = Cal.list_events_for_range(monday, sunday)

    # Calculate mood/energy trends
    mood_data = journal_entries |> Enum.map(& &1.mood) |> Enum.reject(&is_nil/1)
    energy_data = journal_entries |> Enum.map(& &1.energy) |> Enum.reject(&is_nil/1)

    {:ok, %{
      week: "#{monday} to #{sunday}",
      is_current_week: offset == 0,
      journal: %{
        entries_count: length(journal_entries),
        average_mood: calculate_average_from_list(mood_data),
        average_energy: calculate_average_from_list(energy_data)
      },
      finance: %{
        income: Decimal.to_string(Decimal.round(finance_summary.income, 2)),
        expenses: Decimal.to_string(Decimal.round(finance_summary.expenses, 2)),
        balance: Decimal.to_string(Decimal.round(finance_summary.balance, 2))
      },
      events: %{
        total: length(events),
        events: Enum.map(events, fn e ->
          %{title: e.title, date: DateTime.to_date(e.start_at)}
        end)
      }
    }}
  end

  # Helper functions

  defp calculate_average([], _fun), do: 0
  defp calculate_average(list, fun) do
    total = Enum.reduce(list, 0, fn item, acc -> acc + fun.(item) end)
    Float.round(total / length(list), 1)
  end

  defp calculate_average_from_list([]), do: nil
  defp calculate_average_from_list(list) do
    Float.round(Enum.sum(list) / length(list), 1)
  end

  defp calculate_savings_rate(income, expenses) do
    income_float = Decimal.to_float(income)
    expenses_float = Decimal.to_float(expenses)

    if income_float > 0 do
      rate = (income_float - expenses_float) / income_float * 100
      "#{Float.round(rate, 1)}%"
    else
      "N/A"
    end
  end

  defp generate_productivity_insights(habit_stats, goal_stats) do
    insights = []

    insights = if habit_stats.completed_today == habit_stats.total do
      ["All habits completed today!" | insights]
    else
      pending = habit_stats.total - habit_stats.completed_today
      ["#{pending} habit(s) remaining today" | insights]
    end

    insights = if habit_stats.best_streak >= 7 do
      ["Great streak! #{habit_stats.best_streak} days on your best habit" | insights]
    else
      insights
    end

    insights = if goal_stats.average_progress >= 50 do
      ["Good progress on goals - #{goal_stats.average_progress}% average" | insights]
    else
      ["Goals need attention - only #{goal_stats.average_progress}% average progress" | insights]
    end

    insights
  end

  defp generate_finance_insights(summary, category_analysis) do
    insights = []
    balance = Decimal.to_float(summary.balance)
    income = Decimal.to_float(summary.income)

    insights = if balance > 0 do
      ["Positive balance this period!" | insights]
    else
      ["Spending exceeds income" | insights]
    end

    # Find top spending category
    case Enum.at(category_analysis, 0) do
      nil -> insights
      top ->
        if top.percentage > 30 do
          ["#{top.category_label} is #{top.percentage}% of spending" | insights]
        else
          insights
        end
    end
  end

  defp day_of_week(date) do
    case Date.day_of_week(date) do
      1 -> "Monday"
      2 -> "Tuesday"
      3 -> "Wednesday"
      4 -> "Thursday"
      5 -> "Friday"
      6 -> "Saturday"
      7 -> "Sunday"
    end
  end

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M")
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
