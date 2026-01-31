defmodule Aurora.Assistant.ToolRegistry do
  @moduledoc """
  Central registry of all tools available to the AI assistant.
  Tools are defined using Claude's tool format.
  """

  alias Aurora.Assistant.Tools.{
    BoardsTools,
    GoalsTools,
    HabitsTools,
    JournalTools,
    FinanceTools,
    CalendarTools,
    AnalyticsTools
  }

  @doc """
  Returns all tool definitions for the Claude API.
  """
  def all_tools do
    [
      BoardsTools.definitions(),
      GoalsTools.definitions(),
      HabitsTools.definitions(),
      JournalTools.definitions(),
      FinanceTools.definitions(),
      CalendarTools.definitions(),
      AnalyticsTools.definitions()
    ]
    |> List.flatten()
  end

  @doc """
  Returns tool definitions relevant to a user query.
  Analyzes the query to determine which tool modules are needed.
  Returns empty list for conversational messages that don't need tools.
  """
  def tools_for_query(query) do
    query_lower = String.downcase(query)

    # First check if this is a conversational message that doesn't need tools
    if conversational_only?(query_lower) do
      []
    else
      select_tool_modules(query_lower)
    end
  end

  # Detect messages that are purely conversational and don't need tools
  defp conversational_only?(query) do
    # Very short messages are usually greetings/acknowledgments
    word_count = query |> String.split() |> length()

    cond do
      # Short greetings and acknowledgments
      word_count <= 3 and matches_any?(query, ~w(hi hello hey thanks thank you ok okay sure yes no bye goodbye)) ->
        true

      # Questions about the assistant itself
      matches_any?(query, ~w(who are you what are you your name how do you)) and not needs_data?(query) ->
        true

      # General chitchat without action words
      not has_action_intent?(query) and not needs_data?(query) ->
        true

      true ->
        false
    end
  end

  # Check if query has intent to perform an action
  defp has_action_intent?(query) do
    action_words = ~w(
      create add make new delete remove update edit change set
      show list get fetch find check view see display
      mark complete toggle done finish start stop
      move put assign schedule record log track
    )
    matches_any?(query, action_words)
  end

  # Check if query is asking for data/information from the system
  defp needs_data?(query) do
    data_indicators = ~w(
      my what how many how much status progress today
      habit goal task board journal finance calendar event
      expense income budget streak pending overdue upcoming
      summary report week month
    )
    matches_any?(query, data_indicators)
  end

  defp select_tool_modules(query_lower) do
    modules = []

    # Analytics for summaries and reports
    modules = if matches_any?(query_lower, ~w(summary report analyze insight overview status)) do
      [AnalyticsTools | modules]
    else
      modules
    end

    # Boards/Tasks
    modules = if matches_any?(query_lower, ~w(task board column kanban todo card move priority due)) do
      [BoardsTools | modules]
    else
      modules
    end

    # Goals
    modules = if matches_any?(query_lower, ~w(goal quest objective target progress milestone)) do
      [GoalsTools | modules]
    else
      modules
    end

    # Habits
    modules = if matches_any?(query_lower, ~w(habit ritual routine streak)) do
      [HabitsTools | modules]
    else
      modules
    end

    # Journal
    modules = if matches_any?(query_lower, ~w(journal entry diary chronicle mood energy reflect)) do
      [JournalTools | modules]
    else
      modules
    end

    # Finance
    modules = if matches_any?(query_lower, ~w(finance money expense income budget spend transaction treasury dollar payment)) do
      [FinanceTools | modules]
    else
      modules
    end

    # Calendar
    modules = if matches_any?(query_lower, ~w(calendar event schedule meeting appointment remind)) do
      [CalendarTools | modules]
    else
      modules
    end

    # If query seems to need data but no specific module matched, include core set
    modules = if modules == [] and (has_action_intent?(query_lower) or needs_data?(query_lower)) do
      [BoardsTools, HabitsTools, AnalyticsTools]
    else
      modules
    end

    modules
    |> Enum.uniq()
    |> Enum.flat_map(& &1.definitions())
  end

  defp matches_any?(text, keywords) do
    Enum.any?(keywords, &String.contains?(text, &1))
  end

  @doc """
  Returns tools that require user confirmation before execution.
  All tools that modify data require confirmation.
  """
  def destructive_tools do
    MapSet.new([
      "delete_board",
      "delete_column",
      "delete_task",
      "delete_goal",
      "delete_habit",
      "delete_journal_entry",
      "delete_transaction",
      "delete_calendar_event"
    ])
  end

  @doc """
  Checks if a tool requires confirmation.
  All tools require confirmation to prevent unintended actions.
  """
  def requires_confirmation?(_tool_name) do
    # All tools require confirmation
    true
  end

  @doc """
  Checks if a tool is destructive (for UI warning).
  """
  def is_destructive?(tool_name) do
    MapSet.member?(destructive_tools(), tool_name)
  end

  @doc """
  Executes a tool by name with given arguments.
  """
  def execute(tool_name, args) do
    case tool_module(tool_name) do
      nil ->
        {:error, "Unknown tool: #{tool_name}"}

      module ->
        try do
          module.execute(tool_name, args)
        rescue
          e ->
            {:error, "Tool execution failed: #{Exception.message(e)}"}
        end
    end
  end

  @doc """
  Gets a description of what a tool does.
  """
  def get_tool_description(tool_name) do
    all_tools()
    |> Enum.find(fn tool -> tool.name == tool_name end)
    |> case do
      nil -> nil
      tool -> tool.description
    end
  end

  defp tool_module(tool_name) do
    cond do
      String.starts_with?(tool_name, "list_boards") or
        String.starts_with?(tool_name, "get_board") or
        String.starts_with?(tool_name, "create_board") or
        String.starts_with?(tool_name, "update_board") or
        String.starts_with?(tool_name, "delete_board") or
        String.starts_with?(tool_name, "list_columns") or
        String.starts_with?(tool_name, "create_column") or
        String.starts_with?(tool_name, "delete_column") or
        String.starts_with?(tool_name, "list_tasks") or
        String.starts_with?(tool_name, "get_task") or
        String.starts_with?(tool_name, "create_task") or
        String.starts_with?(tool_name, "update_task") or
        String.starts_with?(tool_name, "move_task") or
          String.starts_with?(tool_name, "delete_task") ->
        BoardsTools

      String.starts_with?(tool_name, "list_goals") or
        String.starts_with?(tool_name, "get_goal") or
        String.starts_with?(tool_name, "create_goal") or
        String.starts_with?(tool_name, "update_goal") or
          String.starts_with?(tool_name, "delete_goal") ->
        GoalsTools

      String.starts_with?(tool_name, "list_habits") or
        String.starts_with?(tool_name, "get_habit") or
        String.starts_with?(tool_name, "create_habit") or
        String.starts_with?(tool_name, "update_habit") or
        String.starts_with?(tool_name, "delete_habit") or
          String.starts_with?(tool_name, "toggle_habit") ->
        HabitsTools

      String.starts_with?(tool_name, "list_journal") or
        String.starts_with?(tool_name, "get_journal") or
        String.starts_with?(tool_name, "create_journal") or
        String.starts_with?(tool_name, "update_journal") or
          String.starts_with?(tool_name, "delete_journal") ->
        JournalTools

      String.starts_with?(tool_name, "list_transactions") or
        String.starts_with?(tool_name, "get_transaction") or
        String.starts_with?(tool_name, "create_transaction") or
        String.starts_with?(tool_name, "update_transaction") or
        String.starts_with?(tool_name, "delete_transaction") or
          String.starts_with?(tool_name, "get_finance") ->
        FinanceTools

      String.starts_with?(tool_name, "list_calendar") or
        String.starts_with?(tool_name, "get_calendar") or
        String.starts_with?(tool_name, "create_calendar") or
        String.starts_with?(tool_name, "update_calendar") or
        String.starts_with?(tool_name, "delete_calendar") or
          String.starts_with?(tool_name, "list_upcoming") ->
        CalendarTools

      String.starts_with?(tool_name, "analyze") or
        String.starts_with?(tool_name, "get_daily") or
          String.starts_with?(tool_name, "get_weekly") ->
        AnalyticsTools

      true ->
        nil
    end
  end
end
