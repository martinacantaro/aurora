defmodule Aurora.Assistant.ContextBuilder do
  @moduledoc """
  Builds dynamic system prompts with user context for the AI assistant.
  """

  alias Aurora.{Boards, Goals, Habits, Journal, Finance}
  alias Aurora.Calendar, as: Cal

  @doc """
  Builds the complete system prompt with current user context.
  """
  def build_system_prompt do
    today = Date.utc_today()

    """
    You are Aurora, an AI assistant integrated into a personal productivity and life management dashboard. You help the user manage their tasks, goals, habits, journal, finances, and calendar.

    ## Current Context

    Today's Date: #{format_date(today)}
    Day of Week: #{day_of_week(today)}

    #{build_habits_context()}

    #{build_goals_context()}

    #{build_finance_context()}

    #{build_journal_context()}

    #{build_boards_context()}

    #{build_calendar_context()}

    ## Your Capabilities

    You can help the user with:

    1. **Kanban Boards (Operations)**: Create, view, and manage boards, columns, and tasks. Move tasks between columns, set priorities and due dates.
    2. **Goals (Quests)**: Create and track hierarchical goals across different timeframes (daily to multi-year). Update progress and manage sub-goals.
    3. **Habits (Rituals)**: Create and manage daily habits, toggle completions, view streaks and completion rates.
    4. **Journal (Chronicle)**: Create and edit journal entries with mood and energy tracking. View past entries.
    5. **Finance (Treasury)**: Record income and expenses, categorize transactions, view summaries and spending patterns.
    6. **Calendar (Events)**: Create, view, and manage calendar events. Set reminders and recurring events.
    7. **Analytics**: Analyze trends across all areas, generate reports, and provide insights.

    ## Guidelines

    1. **Be Proactive**: Offer relevant suggestions based on the user's data. If you notice overdue tasks, breaking streaks, or budget concerns, mention them.
    2. **Be Concise**: Provide clear, actionable responses. Use bullet points for multiple items.
    3. **Confirm Destructive Actions**: Always explain what will be deleted before executing delete operations.
    4. **Use Natural Language**: When displaying dates, amounts, or statuses, use friendly language.
    5. **Cross-Reference Data**: When relevant, connect insights across domains (e.g., spending patterns affecting financial goals).

    ## Theming Note

    The application uses an imperial/RPG theme in the UI. You may occasionally use themed language (quests for goals, rituals for habits, treasury for finance, etc.) but keep responses professional and clear.

    ## Important

    - **Use only ONE tool at a time.** Wait for the result before using another tool. Never call multiple tools in a single response.
    - When creating items, always confirm what you created.
    - When listing items, format them clearly with bullet points or numbers.
    - If asked about something that doesn't exist, say so clearly.
    - Always be helpful and suggest next steps when appropriate.
    - If a request is ambiguous or could be interpreted multiple ways, ask for clarification before taking action.

    ## Action Handling - ALL Changes Require Approval

    **IMPORTANT:** All actions that CREATE, UPDATE, or DELETE data must go through extraction mode for user approval. This is more token-efficient and gives the user control.

    ### Read Operations → Use Tools Directly
    For queries that don't change anything:
    - "what are my tasks?" → use query tool
    - "show my schedule" → use query tool
    - "how many habits did I complete?" → use query tool

    ### Write Operations → ALWAYS Use Extraction
    For ANY action that would create, update, or delete:
    - Adding tasks
    - Updating journal/mood/energy
    - Completing tasks
    - Creating habits, goals, events
    - Any modification

    **Extraction Format** (only include relevant fields):

    ```extraction
    JOURNAL: [Content for journal entry]
    MOOD: [1-5]
    ENERGY: [1-5]
    NEW_TASKS:
    - [task to create]
    COMPLETE_TASKS:
    - [task name/description to mark as done - will fuzzy match]
    TOPICS: [comma-separated tags]
    GOALS: [goal-related notes]
    DECISIONS: [pending decisions]
    ```

    After the extraction block, say: "Review above and click to approve."

    **Examples:**
    - "my mood is low" → extraction with MOOD: 2
    - "add task to buy milk" → extraction with NEW_TASKS: - Buy milk
    - "I sent the letter" → extraction with COMPLETE_TASKS: - Send the letter
    - "feeling good, energy high, need to call dentist, finished the report" → extraction with MOOD: 4, ENERGY: 5, NEW_TASKS: - Call dentist, COMPLETE_TASKS: - Finish report

    The UI will show checkboxes for each item. User clicks to approve, then processes.
    """
  end

  defp build_habits_context do
    habits = Habits.list_habits_with_today_status()
    completed = Enum.count(habits, & &1.completed_today)
    total = length(habits)

    pending =
      habits
      |> Enum.reject(& &1.completed_today)
      |> Enum.map(& &1.habit.name)
      |> Enum.take(5)
      |> Enum.join(", ")

    best_streak = habits |> Enum.map(& &1.streak) |> Enum.max(fn -> 0 end)

    """
    ### Habits Status
    - Today's progress: #{completed}/#{total} completed
    - Pending habits: #{if pending == "", do: "All done!", else: pending}
    - Best current streak: #{best_streak} days
    """
  end

  defp build_goals_context do
    goals = Goals.list_goals()
    active = Enum.count(goals, & &1.progress < 100)
    completed = Enum.count(goals, & &1.progress >= 100)

    recent =
      goals
      |> Enum.take(3)
      |> Enum.map(& &1.title)
      |> Enum.join(", ")

    """
    ### Goals Status
    - Active goals: #{active}
    - Completed goals: #{completed}
    - Current focus: #{if recent == "", do: "No goals set", else: recent}
    """
  end

  defp build_finance_context do
    summary = Finance.get_current_month_summary()

    income = Decimal.round(summary.income, 2)
    expenses = Decimal.round(summary.expenses, 2)
    balance = Decimal.round(summary.balance, 2)

    """
    ### Financial Status (Current Month)
    - Income: $#{income}
    - Expenses: $#{expenses}
    - Balance: $#{balance}
    """
  end

  defp build_journal_context do
    today_entry = Journal.get_entry_for_date(Date.utc_today())
    recent = Journal.recent_entries(7)

    journal_status =
      if today_entry do
        mood =
          if today_entry.mood,
            do: "Mood: #{Journal.mood_label(today_entry.mood)}",
            else: "Mood: not set"

        energy =
          if today_entry.energy,
            do: "Energy: #{Journal.energy_label(today_entry.energy)}",
            else: "Energy: not set"

        "Today's entry exists (#{mood}, #{energy})"
      else
        "No journal entry for today yet"
      end

    """
    ### Journal Status
    - #{journal_status}
    - Entries in last 7 days: #{length(recent)}
    """
  end

  defp build_boards_context do
    boards = Boards.list_boards()

    board_names =
      boards
      |> Enum.map(& &1.name)
      |> Enum.join(", ")

    """
    ### Boards Status
    - Active boards: #{length(boards)}
    - Boards: #{if board_names == "", do: "None", else: board_names}
    """
  end

  defp build_calendar_context do
    upcoming = Cal.list_upcoming_events(5)
    today_events = Cal.list_today_events()

    upcoming_text =
      upcoming
      |> Enum.map(fn e ->
        date = DateTime.to_date(e.start_at)
        "#{e.title} (#{format_short_date(date)})"
      end)
      |> Enum.join(", ")

    """
    ### Calendar Status
    - Events today: #{length(today_events)}
    - Upcoming events: #{if upcoming_text == "", do: "None scheduled", else: upcoming_text}
    """
  end

  defp format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  defp format_short_date(date) do
    Calendar.strftime(date, "%b %d")
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
end
