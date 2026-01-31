defmodule AuroraWeb.AssistantLive.Index do
  use AuroraWeb, :live_view

  alias Aurora.Assistant
  alias Aurora.Assistant.{ClaudeClient, ContextBuilder, ToolRegistry}
  alias Aurora.{Notes, Journal, Boards}

  @impl true
  def mount(_params, _session, socket) do
    # Get or create a default conversation
    {:ok, conversation} = Assistant.get_or_create_default_conversation()
    messages = Assistant.list_messages(conversation.id)

    {:ok,
     socket
     |> assign(:page_title, "Aurora AI")
     |> assign(:conversations, Assistant.list_conversations())
     |> assign(:current_conversation, conversation)
     |> assign(:messages, messages)
     |> assign(:input_text, "")
     |> assign(:is_loading, false)
     |> assign(:streaming_content, "")
     |> assign(:pending_tool_call, nil)
     |> assign(:pending_assistant_content, nil)
     |> assign(:error_message, nil)
     |> assign(:is_recording, false)
     |> assign(:pending_extraction, nil)
     |> assign(:last_voice_input, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case Assistant.get_conversation(id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Conversation not found")
         |> push_navigate(to: ~p"/assistant")}

      conversation ->
        messages = Assistant.list_messages(conversation.id)

        {:noreply,
         socket
         |> assign(:current_conversation, conversation)
         |> assign(:messages, messages)}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("new_conversation", _params, socket) do
    {:ok, conversation} = Assistant.create_conversation(%{title: "New Conversation"})

    {:noreply,
     socket
     |> assign(:current_conversation, conversation)
     |> assign(:messages, [])
     |> assign(:conversations, Assistant.list_conversations())
     |> push_patch(to: ~p"/assistant/#{conversation.id}")}
  end

  @impl true
  def handle_event("select_conversation", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/assistant/#{id}")}
  end

  @impl true
  def handle_event("delete_conversation", %{"id" => id}, socket) do
    conversation = Assistant.get_conversation!(id)
    Assistant.delete_conversation(conversation)

    # Get or create new conversation if we deleted the current one
    {:ok, new_conversation} = Assistant.get_or_create_default_conversation()

    {:noreply,
     socket
     |> assign(:conversations, Assistant.list_conversations())
     |> assign(:current_conversation, new_conversation)
     |> assign(:messages, Assistant.list_messages(new_conversation.id))
     |> put_flash(:info, "Conversation deleted")}
  end

  @impl true
  def handle_event("send_message", %{"message" => ""}, socket), do: {:noreply, socket}

  def handle_event("send_message", %{"message" => content}, socket) do
    conversation = socket.assigns.current_conversation

    # Create user message
    {:ok, user_message} = Assistant.add_user_message(conversation.id, content)

    # Update UI immediately
    messages = socket.assigns.messages ++ [user_message]

    # Start generating response
    send(self(), :generate_response)

    {:noreply,
     socket
     |> assign(:messages, messages)
     |> assign(:input_text, "")
     |> assign(:is_loading, true)
     |> assign(:streaming_content, "")
     |> assign(:error_message, nil)}
  end

  @impl true
  def handle_event("confirm_tool_call", _params, socket) do
    pending = socket.assigns.pending_tool_call

    # Execute the tool
    case ToolRegistry.execute(pending.name, pending.input) do
      {:ok, result} ->
        # Continue conversation with tool result
        send(self(), {:continue_with_tool_result, pending.id, {:ok, result}})

        {:noreply,
         socket
         |> assign(:pending_tool_call, nil)
         |> assign(:is_loading, true)}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:pending_tool_call, nil)
         |> assign(:error_message, "Tool execution failed: #{error}")}
    end
  end

  @impl true
  def handle_event("cancel_tool_call", _params, socket) do
    {:noreply,
     socket
     |> assign(:pending_tool_call, nil)
     |> assign(:is_loading, false)}
  end

  @impl true
  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :error_message, nil)}
  end

  @impl true
  def handle_event("voice_recording_started", _params, socket) do
    {:noreply, assign(socket, :is_recording, true)}
  end

  @impl true
  def handle_event("voice_recording_stopped", _params, socket) do
    {:noreply, assign(socket, :is_recording, false)}
  end

  @impl true
  def handle_event("voice_input", %{"text" => ""}, socket), do: {:noreply, socket}

  def handle_event("voice_input", %{"text" => text}, socket) do
    # Save transcription to file
    Notes.save_transcription(text)

    # Store for extraction processing
    socket = assign(socket, :last_voice_input, text)

    # Send as message
    handle_event("send_message", %{"message" => text}, socket)
  end

  @impl true
  def handle_info(:generate_response, socket) do
    try do
      conversation = socket.assigns.current_conversation
      messages = Assistant.get_recent_messages(conversation.id, 10)
      api_messages = Assistant.format_messages_for_api(messages)

      # Get the last user message to analyze intent
      last_user_message = messages |> Enum.filter(&(&1.role == "user")) |> List.last()
      query = if last_user_message, do: last_user_message.content, else: ""

      # First, analyze if this message needs tools using Claude
      tools = case ClaudeClient.analyze_intent(query) do
        {:ok, :needs_tools} ->
          ToolRegistry.tools_for_query(query)
        {:ok, :conversation_only} ->
          []
      end

      system_prompt = ContextBuilder.build_system_prompt()

      case ClaudeClient.create_message(api_messages, system_prompt: system_prompt, tools: tools) do
        {:ok, response} ->
          handle_api_response(socket, response)

        {:error, error} ->
          {:noreply,
           socket
           |> assign(:is_loading, false)
           |> assign(:error_message, "API Error: #{error}")}
      end
    rescue
      e ->
        {:noreply,
         socket
         |> assign(:is_loading, false)
         |> assign(:error_message, "Error: #{Exception.message(e)}")}
    end
  end

  @impl true
  def handle_info({:continue_with_tool_result, tool_use_id, result}, socket) do
    try do
      conversation = socket.assigns.current_conversation
      messages = Assistant.get_recent_messages(conversation.id, 10)
      api_messages = Assistant.format_messages_for_api(messages)

      # Replace the last assistant message with the full content (including tool_use blocks)
      # The DB only has text, but we need the tool_use blocks for the API
      api_messages = case socket.assigns.pending_assistant_content do
        nil ->
          api_messages

        content ->
          # Remove the last assistant message (text-only from DB) and replace with full content
          api_messages
          |> Enum.reverse()
          |> drop_last_assistant_message()
          |> Enum.reverse()
          |> Kernel.++([%{"role" => "assistant", "content" => content}])
      end

      # Get the last user message to determine relevant tools
      last_user_message = messages |> Enum.filter(&(&1.role == "user")) |> List.last()
      query = if last_user_message, do: last_user_message.content, else: ""

      system_prompt = ContextBuilder.build_system_prompt()
      tools = ToolRegistry.tools_for_query(query)

      # Format tool result
      tool_result_message = %{
        "role" => "user",
        "content" => [
          %{
            "type" => "tool_result",
            "tool_use_id" => tool_use_id,
            "content" => format_tool_result_content(result)
          }
        ]
      }

      case ClaudeClient.create_message(api_messages ++ [tool_result_message],
             system_prompt: system_prompt,
             tools: tools
           ) do
        {:ok, response} ->
          socket = assign(socket, :pending_assistant_content, nil)
          handle_api_response(socket, response)

        {:error, error} ->
          {:noreply,
           socket
           |> assign(:is_loading, false)
           |> assign(:pending_assistant_content, nil)
           |> assign(:error_message, "API Error: #{error}")}
      end
    rescue
      e ->
        {:noreply,
         socket
         |> assign(:is_loading, false)
         |> assign(:pending_assistant_content, nil)
         |> assign(:error_message, "Error: #{Exception.message(e)}")}
    end
  end

  # Drop the first assistant message found (list is reversed, so this is the last one)
  defp drop_last_assistant_message([%{"role" => "assistant"} | rest]), do: rest
  defp drop_last_assistant_message([msg | rest]), do: [msg | drop_last_assistant_message(rest)]
  defp drop_last_assistant_message([]), do: []

  defp format_tool_result_content({:ok, result}) when is_map(result), do: Jason.encode!(result)
  defp format_tool_result_content({:ok, result}), do: to_string(result)
  defp format_tool_result_content({:error, error}), do: "Error: #{error}"

  defp handle_api_response(socket, response) do
    conversation = socket.assigns.current_conversation

    # Process content blocks
    {text_content, tool_uses} =
      Enum.reduce(response.content, {"", []}, fn block, {text, tools} ->
        case block do
          %{type: :text, text: t} -> {text <> t, tools}
          %{type: :tool_use} = tool -> {text, [tool | tools]}
          _ -> {text, tools}
        end
      end)

    # Save assistant message if there's text
    socket =
      if text_content != "" do
        {:ok, assistant_message} =
          Assistant.add_assistant_message(conversation.id, text_content,
            input_tokens: response.usage["input_tokens"],
            output_tokens: response.usage["output_tokens"]
          )

        messages = socket.assigns.messages ++ [assistant_message]

        # Check for extraction block and parse it
        extraction = parse_extraction(text_content)

        socket
        |> assign(:messages, messages)
        |> assign(:pending_extraction, extraction)
      else
        socket
      end

    # Handle tool uses - process ONE at a time to avoid mismatched tool_use/tool_result
    case tool_uses do
      [] ->
        {:noreply, assign(socket, :is_loading, false)}

      [tool_use | _remaining_tools] ->
        # Build content with ONLY the text and the ONE tool_use we're processing
        # This avoids the "tool_use without tool_result" error when Claude returns multiple tools
        api_content = build_api_content_single_tool(response.content, tool_use.id)
        socket = assign(socket, :pending_assistant_content, api_content)

        if ToolRegistry.requires_confirmation?(tool_use.name) do
          {:noreply,
           socket
           |> assign(:is_loading, false)
           |> assign(:pending_tool_call, %{
             id: tool_use.id,
             name: tool_use.name,
             input: tool_use.input
           })}
        else
          # Execute immediately
          case ToolRegistry.execute(tool_use.name, tool_use.input) do
            {:ok, result} ->
              send(self(), {:continue_with_tool_result, tool_use.id, {:ok, result}})
              {:noreply, socket}

            {:error, error} ->
              send(self(), {:continue_with_tool_result, tool_use.id, {:error, error}})
              {:noreply, socket}
          end
        end
    end
  end

  # Build content array with only ONE specific tool_use (to avoid mismatched tool_use/tool_result)
  defp build_api_content_single_tool(content_blocks, tool_use_id) do
    Enum.map(content_blocks, fn
      %{type: :text, text: text} ->
        %{"type" => "text", "text" => text}

      %{type: :tool_use, id: id, name: name, input: input} when id == tool_use_id ->
        %{"type" => "tool_use", "id" => id, "name" => name, "input" => input}

      %{type: :tool_use} ->
        # Skip other tool_use blocks - we'll handle them one at a time
        nil

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M")
  end

  defp format_tool_name(name) do
    name
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  # Extraction parsing
  defp parse_extraction(text) do
    if String.contains?(text, "```extraction") do
      # Extract the block between ```extraction and ```
      case Regex.run(~r/```extraction\n(.*?)\n```/s, text) do
        [_, content] -> parse_extraction_content(content)
        _ -> nil
      end
    else
      nil
    end
  end

  defp parse_extraction_content(content) do
    lines = String.split(content, "\n")

    extraction = %{
      journal: nil,
      mood: nil,
      energy: nil,
      new_tasks: [],
      complete_tasks: [],
      topics: [],
      goals: nil,
      decisions: nil,
      approved: %{
        journal: false,
        new_tasks: MapSet.new(),
        complete_tasks: MapSet.new()
      }
    }

    parse_extraction_lines(lines, extraction, nil)
  end

  defp parse_extraction_lines([], extraction, _current_section), do: extraction

  defp parse_extraction_lines([line | rest], extraction, current_section) do
    line = String.trim(line)

    cond do
      String.starts_with?(line, "JOURNAL:") ->
        value = String.trim(String.replace_prefix(line, "JOURNAL:", ""))
        extraction = %{extraction | journal: value}
        parse_extraction_lines(rest, extraction, :journal)

      String.starts_with?(line, "MOOD:") ->
        value = String.trim(String.replace_prefix(line, "MOOD:", ""))
        mood = parse_mood_energy(value)
        extraction = %{extraction | mood: mood}
        parse_extraction_lines(rest, extraction, nil)

      String.starts_with?(line, "ENERGY:") ->
        value = String.trim(String.replace_prefix(line, "ENERGY:", ""))
        energy = parse_mood_energy(value)
        extraction = %{extraction | energy: energy}
        parse_extraction_lines(rest, extraction, nil)

      String.starts_with?(line, "NEW_TASKS:") or String.starts_with?(line, "TASKS:") ->
        parse_extraction_lines(rest, extraction, :new_tasks)

      String.starts_with?(line, "COMPLETE_TASKS:") ->
        parse_extraction_lines(rest, extraction, :complete_tasks)

      String.starts_with?(line, "TOPICS:") ->
        value = String.trim(String.replace_prefix(line, "TOPICS:", ""))
        topics = value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
        extraction = %{extraction | topics: topics}
        parse_extraction_lines(rest, extraction, nil)

      String.starts_with?(line, "GOALS:") ->
        value = String.trim(String.replace_prefix(line, "GOALS:", ""))
        extraction = %{extraction | goals: value}
        parse_extraction_lines(rest, extraction, nil)

      String.starts_with?(line, "DECISIONS:") ->
        value = String.trim(String.replace_prefix(line, "DECISIONS:", ""))
        extraction = %{extraction | decisions: value}
        parse_extraction_lines(rest, extraction, nil)

      String.starts_with?(line, "- ") and current_section == :new_tasks ->
        task = String.trim(String.replace_prefix(line, "- ", ""))
        extraction = %{extraction | new_tasks: extraction.new_tasks ++ [task]}
        parse_extraction_lines(rest, extraction, :new_tasks)

      String.starts_with?(line, "- ") and current_section == :complete_tasks ->
        task = String.trim(String.replace_prefix(line, "- ", ""))
        extraction = %{extraction | complete_tasks: extraction.complete_tasks ++ [task]}
        parse_extraction_lines(rest, extraction, :complete_tasks)

      true ->
        parse_extraction_lines(rest, extraction, current_section)
    end
  end

  defp parse_mood_energy(value) do
    case Integer.parse(value) do
      {n, _} when n >= 1 and n <= 5 -> n
      _ -> nil
    end
  end

  # Extraction event handlers
  @impl true
  def handle_event("toggle_extraction_journal", _params, socket) do
    extraction = socket.assigns.pending_extraction
    approved = extraction.approved
    new_approved = %{approved | journal: !approved.journal}
    extraction = %{extraction | approved: new_approved}
    {:noreply, assign(socket, :pending_extraction, extraction)}
  end

  @impl true
  def handle_event("toggle_extraction_task", %{"index" => index, "type" => type}, socket) do
    index = String.to_integer(index)
    extraction = socket.assigns.pending_extraction
    approved = extraction.approved

    key = String.to_existing_atom(type)
    current_set = Map.get(approved, key, MapSet.new())

    new_set =
      if MapSet.member?(current_set, index) do
        MapSet.delete(current_set, index)
      else
        MapSet.put(current_set, index)
      end

    new_approved = Map.put(approved, key, new_set)
    extraction = %{extraction | approved: new_approved}
    {:noreply, assign(socket, :pending_extraction, extraction)}
  end

  @impl true
  def handle_event("process_extraction", _params, socket) do
    extraction = socket.assigns.pending_extraction

    # Process approved journal (includes mood/energy even without journal text)
    if extraction.approved.journal do
      {:ok, entry} = Journal.get_or_create_entry_for_date(Date.utc_today())

      # Build update attrs - only include fields that have values
      update_attrs = %{}
      update_attrs = if extraction.journal, do: Map.put(update_attrs, :content, extraction.journal), else: update_attrs
      update_attrs = if extraction.mood, do: Map.put(update_attrs, :mood, extraction.mood), else: update_attrs
      update_attrs = if extraction.energy, do: Map.put(update_attrs, :energy, extraction.energy), else: update_attrs

      if map_size(update_attrs) > 0 do
        Journal.update_entry(entry, update_attrs)
      end
    end

    # Process approved new tasks
    default_column = get_default_column()

    if default_column do
      extraction.new_tasks
      |> Enum.with_index()
      |> Enum.filter(fn {_task, index} -> MapSet.member?(extraction.approved.new_tasks, index) end)
      |> Enum.each(fn {task_title, _index} ->
        Boards.create_task(%{
          title: task_title,
          column_id: default_column.id,
          position: 0
        })
      end)
    end

    # Process approved complete tasks (fuzzy match and mark as done)
    extraction.complete_tasks
    |> Enum.with_index()
    |> Enum.filter(fn {_task, index} -> MapSet.member?(extraction.approved.complete_tasks, index) end)
    |> Enum.each(fn {task_description, _index} ->
      complete_task_by_fuzzy_match(task_description)
    end)

    {:noreply,
     socket
     |> assign(:pending_extraction, nil)
     |> put_flash(:info, "Extraction processed successfully")}
  end

  defp complete_task_by_fuzzy_match(description) do
    # Find incomplete tasks and fuzzy match by title
    case Boards.list_boards() do
      [] -> :ok
      boards ->
        boards
        |> Enum.flat_map(fn board ->
          board = Boards.get_board!(board.id)
          board.columns
          |> Enum.flat_map(fn column -> column.tasks end)
        end)
        |> Enum.reject(& &1.completed)
        |> Enum.find(fn task ->
          fuzzy_match?(String.downcase(task.title), String.downcase(description))
        end)
        |> case do
          nil -> :ok
          task -> Boards.toggle_task_completed(task.id)
        end
    end
  end

  defp fuzzy_match?(title, description) do
    # Check if title contains key words from description or vice versa
    title_words = String.split(title, ~r/\s+/) |> MapSet.new()
    desc_words = String.split(description, ~r/\s+/) |> MapSet.new()

    # Match if significant overlap (at least 2 words or 50% of shorter)
    intersection = MapSet.intersection(title_words, desc_words)
    intersection_size = MapSet.size(intersection)
    min_size = min(MapSet.size(title_words), MapSet.size(desc_words))

    intersection_size >= 2 or (min_size > 0 and intersection_size / min_size >= 0.5) or
      String.contains?(title, description) or String.contains?(description, title)
  end

  @impl true
  def handle_event("dismiss_extraction", _params, socket) do
    {:noreply, assign(socket, :pending_extraction, nil)}
  end

  defp get_default_column do
    case Boards.list_boards() do
      [board | _] ->
        board = Boards.get_board!(board.id)
        case board.columns do
          [column | _] -> column
          _ -> nil
        end
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-base-300">
      <!-- Sidebar: Conversation List -->
      <div class="w-64 bg-base-200 border-r border-primary/20 flex flex-col">
        <div class="p-4 border-b border-primary/20">
          <.link navigate={~p"/"} class="flex items-center gap-2 text-primary mb-4">
            <.icon name="hero-arrow-left" class="w-4 h-4" />
            <span class="text-sm">Back to Dashboard</span>
          </.link>
          <button phx-click="new_conversation" class="btn btn-imperial-primary w-full">
            <.icon name="hero-plus" class="w-4 h-4" />
            New Chat
          </button>
        </div>
        <div class="flex-1 overflow-y-auto p-2">
          <%= for conv <- @conversations do %>
            <div class={"flex items-center gap-1 rounded mb-1 hover:bg-primary/10 #{if @current_conversation && @current_conversation.id == conv.id, do: "bg-primary/20 border border-primary/30", else: ""}"}>
              <button
                phx-click="select_conversation"
                phx-value-id={conv.id}
                class="flex-1 p-3 text-left"
              >
                <div class="text-sm font-medium truncate">
                  <%= conv.title || "Untitled" %>
                </div>
                <div class="text-xs text-base-content/50">
                  <%= Calendar.strftime(conv.updated_at, "%b %d, %H:%M") %>
                </div>
              </button>
              <button
                phx-click="delete_conversation"
                phx-value-id={conv.id}
                data-confirm="Delete this conversation?"
                class="btn btn-ghost btn-xs mr-2"
              >
                <.icon name="hero-trash" class="w-3 h-3 text-error/60" />
              </button>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Main Chat Area -->
      <div class="flex-1 flex flex-col">
        <!-- Header -->
        <header class="border-b border-primary/30 bg-base-200 px-4 py-3">
          <div class="flex items-center gap-3">
            <.icon name="hero-sparkles" class="w-6 h-6 text-primary" />
            <h1 class="text-xl text-primary">Aurora AI</h1>
          </div>
        </header>

        <!-- Messages -->
        <div class="flex-1 overflow-y-auto p-4 space-y-4" id="messages-container" phx-hook="ScrollToBottom">
          <%= if @messages == [] do %>
            <div class="flex flex-col items-center justify-center h-full text-center">
              <.icon name="hero-sparkles" class="w-16 h-16 text-primary/30 mb-4" />
              <h2 class="text-xl text-primary mb-2">Welcome to Aurora AI</h2>
              <p class="text-base-content/60 max-w-md">
                I can help you manage your tasks, habits, goals, journal, finances, and calendar.
                Ask me anything!
              </p>
              <div class="mt-6 grid grid-cols-2 gap-2 text-sm">
                <div class="card card-ornate p-3 text-left">
                  <p class="text-primary font-medium">Try asking:</p>
                  <p class="text-base-content/60">"What are my habits for today?"</p>
                </div>
                <div class="card card-ornate p-3 text-left">
                  <p class="text-primary font-medium">Or:</p>
                  <p class="text-base-content/60">"Create a task to review budget"</p>
                </div>
              </div>
            </div>
          <% else %>
            <%= for message <- @messages do %>
              <div class={"flex #{if message.role == "user", do: "justify-end", else: "justify-start"}"}>
                <div class={"max-w-[80%] #{if message.role == "user", do: "bg-primary/20 border-primary/30", else: "bg-base-200 border-base-content/10"} border rounded-lg p-4"}>
                  <%= if message.role == "assistant" do %>
                    <div class="flex items-center gap-2 mb-2">
                      <.icon name="hero-sparkles" class="w-4 h-4 text-primary" />
                      <span class="text-xs text-primary font-medium">Aurora</span>
                    </div>
                  <% end %>
                  <div class="prose prose-sm max-w-none text-base-content whitespace-pre-wrap">
                    <%= message.content %>
                  </div>
                  <div class="text-xs text-base-content/40 mt-2">
                    <%= format_time(message.inserted_at) %>
                  </div>
                </div>
              </div>
            <% end %>

            <!-- Loading indicator -->
            <%= if @is_loading do %>
              <div class="flex justify-start">
                <div class="bg-base-200 border border-base-content/10 rounded-lg p-4">
                  <div class="flex items-center gap-2">
                    <.icon name="hero-sparkles" class="w-4 h-4 text-primary animate-pulse" />
                    <span class="text-sm text-base-content/60">Aurora is thinking...</span>
                    <span class="loading loading-dots loading-sm"></span>
                  </div>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>

        <!-- Error message -->
        <%= if @error_message do %>
          <div class="px-4 pb-2">
            <div class="alert alert-error">
              <.icon name="hero-exclamation-circle" class="w-5 h-5" />
              <span><%= @error_message %></span>
              <button phx-click="clear_error" class="btn btn-ghost btn-sm">
                <.icon name="hero-x-mark" class="w-4 h-4" />
              </button>
            </div>
          </div>
        <% end %>

        <!-- Extraction Card -->
        <%= if @pending_extraction do %>
          <div class="px-4 pb-2">
            <div class="card card-ornate border border-primary/50 p-4">
              <div class="flex justify-between items-center mb-3">
                <h3 class="text-primary font-semibold flex items-center gap-2">
                  <.icon name="hero-sparkles" class="w-5 h-5" />
                  Extracted Items
                </h3>
                <button phx-click="dismiss_extraction" class="btn btn-ghost btn-xs">
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                </button>
              </div>

              <div class="space-y-3">
                <!-- Journal (or mood/energy only) -->
                <%= if @pending_extraction.journal || @pending_extraction.mood || @pending_extraction.energy do %>
                  <div
                    class={"p-3 rounded border cursor-pointer transition-colors #{if @pending_extraction.approved.journal, do: "border-success bg-success/10", else: "border-base-content/20 hover:border-primary/50"}"}
                    phx-click="toggle_extraction_journal"
                  >
                    <div class="flex items-start gap-2">
                      <div class={"w-5 h-5 rounded border flex-shrink-0 flex items-center justify-center #{if @pending_extraction.approved.journal, do: "bg-success border-success text-success-content", else: "border-base-content/40"}"}>
                        <%= if @pending_extraction.approved.journal do %>
                          <.icon name="hero-check" class="w-3 h-3" />
                        <% end %>
                      </div>
                      <div class="flex-1">
                        <div class="text-xs text-primary font-medium mb-1">📝 Journal Entry</div>
                        <%= if @pending_extraction.journal do %>
                          <div class="text-sm"><%= @pending_extraction.journal %></div>
                        <% end %>
                        <%= if @pending_extraction.mood || @pending_extraction.energy do %>
                          <div class={"text-xs #{if @pending_extraction.journal, do: "text-base-content/60 mt-1", else: "text-sm"}"}>
                            <%= if @pending_extraction.mood do %>
                              <span class="inline-flex items-center gap-1">
                                😊 Mood: <%= @pending_extraction.mood %>/5
                              </span>
                            <% end %>
                            <%= if @pending_extraction.mood && @pending_extraction.energy do %> | <% end %>
                            <%= if @pending_extraction.energy do %>
                              <span class="inline-flex items-center gap-1">
                                ⚡ Energy: <%= @pending_extraction.energy %>/5
                              </span>
                            <% end %>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>
                <% end %>

                <!-- New Tasks -->
                <%= if @pending_extraction.new_tasks != [] do %>
                  <div class="space-y-1">
                    <div class="text-xs text-primary font-medium">➕ New Tasks</div>
                    <%= for {task, index} <- Enum.with_index(@pending_extraction.new_tasks) do %>
                      <% is_approved = MapSet.member?(@pending_extraction.approved.new_tasks, index) %>
                      <div
                        class={"p-2 rounded border cursor-pointer transition-colors #{if is_approved, do: "border-success bg-success/10", else: "border-base-content/20 hover:border-primary/50"}"}
                        phx-click="toggle_extraction_task"
                        phx-value-index={index}
                        phx-value-type="new_tasks"
                      >
                        <div class="flex items-center gap-2">
                          <div class={"w-4 h-4 rounded border flex-shrink-0 flex items-center justify-center #{if is_approved, do: "bg-success border-success text-success-content", else: "border-base-content/40"}"}>
                            <%= if is_approved do %>
                              <.icon name="hero-check" class="w-2.5 h-2.5" />
                            <% end %>
                          </div>
                          <span class="text-sm"><%= task %></span>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <!-- Complete Tasks -->
                <%= if @pending_extraction.complete_tasks != [] do %>
                  <div class="space-y-1">
                    <div class="text-xs text-primary font-medium">✅ Mark as Done</div>
                    <%= for {task, index} <- Enum.with_index(@pending_extraction.complete_tasks) do %>
                      <% is_approved = MapSet.member?(@pending_extraction.approved.complete_tasks, index) %>
                      <div
                        class={"p-2 rounded border cursor-pointer transition-colors #{if is_approved, do: "border-success bg-success/10", else: "border-base-content/20 hover:border-primary/50"}"}
                        phx-click="toggle_extraction_task"
                        phx-value-index={index}
                        phx-value-type="complete_tasks"
                      >
                        <div class="flex items-center gap-2">
                          <div class={"w-4 h-4 rounded border flex-shrink-0 flex items-center justify-center #{if is_approved, do: "bg-success border-success text-success-content", else: "border-base-content/40"}"}>
                            <%= if is_approved do %>
                              <.icon name="hero-check" class="w-2.5 h-2.5" />
                            <% end %>
                          </div>
                          <span class="text-sm"><%= task %></span>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <!-- Topics -->
                <%= if @pending_extraction.topics != [] do %>
                  <div>
                    <div class="text-xs text-primary font-medium mb-1">🏷️ Topics</div>
                    <div class="flex flex-wrap gap-1">
                      <%= for topic <- @pending_extraction.topics do %>
                        <span class="badge badge-sm bg-primary/20 text-primary border-primary/30"><%= topic %></span>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <!-- Goals & Decisions (info only) -->
                <%= if @pending_extraction.goals && @pending_extraction.goals != "" do %>
                  <div class="text-sm">
                    <span class="text-xs text-primary font-medium">🎯 Goals:</span>
                    <span class="text-base-content/80 ml-1"><%= @pending_extraction.goals %></span>
                  </div>
                <% end %>

                <%= if @pending_extraction.decisions && @pending_extraction.decisions != "" do %>
                  <div class="text-sm">
                    <span class="text-xs text-primary font-medium">⚖️ Decisions:</span>
                    <span class="text-base-content/80 ml-1"><%= @pending_extraction.decisions %></span>
                  </div>
                <% end %>
              </div>

              <!-- Action buttons -->
              <div class="flex justify-end gap-2 mt-4 pt-3 border-t border-base-content/10">
                <button phx-click="dismiss_extraction" class="btn btn-ghost btn-sm">
                  Dismiss
                </button>
                <button phx-click="process_extraction" class="btn btn-imperial-primary btn-sm">
                  <.icon name="hero-check" class="w-4 h-4" />
                  Process Selected
                </button>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Input Area -->
        <div class="border-t border-primary/20 p-4 bg-base-200">
          <form phx-submit="send_message" class="flex gap-2">
            <input
              type="text"
              name="message"
              value={@input_text}
              placeholder={if @is_recording, do: "Listening...", else: "Ask Aurora anything..."}
              class="input input-imperial flex-1"
              disabled={@is_loading}
              autocomplete="off"
              autofocus
            />
            <button
              type="button"
              id="voice-input-btn"
              phx-hook="VoiceInput"
              class={"btn #{if @is_recording, do: "btn-error animate-pulse", else: "btn-imperial"}"}
              disabled={@is_loading}
              title={if @is_recording, do: "Click to stop", else: "Click to speak"}
            >
              <.icon name="hero-microphone" class="w-5 h-5" />
            </button>
            <button
              type="submit"
              class="btn btn-imperial-primary"
              disabled={@is_loading}
            >
              <.icon name="hero-paper-airplane" class="w-5 h-5" />
            </button>
          </form>
          <p class="text-xs text-base-content/40 mt-2 text-center">
            <%= if @is_recording do %>
              <span class="text-error">Recording... Click the microphone to stop</span>
            <% else %>
              Aurora can manage your tasks, habits, goals, journal, finances, and calendar.
            <% end %>
          </p>
        </div>
      </div>

      <!-- Tool Confirmation Modal -->
      <%= if @pending_tool_call do %>
        <div class="modal modal-open">
          <div class="modal-box card-ornate border border-primary/50">
            <h3 class="panel-header">Confirm Action</h3>
            <p class="text-base-content/80 mb-4">
              Aurora wants to: <strong class="text-primary"><%= format_tool_name(@pending_tool_call.name) %></strong>
            </p>
            <div class="bg-base-300 p-3 rounded mb-4 font-mono text-sm overflow-x-auto">
              <pre><%= Jason.encode!(@pending_tool_call.input, pretty: true) %></pre>
            </div>
            <%= if String.starts_with?(@pending_tool_call.name, "delete") do %>
              <p class="text-warning text-sm mb-4 flex items-center gap-2">
                <.icon name="hero-exclamation-triangle" class="w-4 h-4" />
                This action cannot be undone.
              </p>
            <% end %>
            <div class="flex justify-end gap-2">
              <button phx-click="cancel_tool_call" class="btn btn-imperial">
                Cancel
              </button>
              <button phx-click="confirm_tool_call" class={"btn #{if String.starts_with?(@pending_tool_call.name, "delete"), do: "btn-imperial-danger", else: "btn-imperial-primary"}"}>
                Confirm
              </button>
            </div>
          </div>
          <div class="modal-backdrop" phx-click="cancel_tool_call"></div>
        </div>
      <% end %>
    </div>
    """
  end
end
