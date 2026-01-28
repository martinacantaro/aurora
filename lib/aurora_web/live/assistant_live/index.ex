defmodule AuroraWeb.AssistantLive.Index do
  use AuroraWeb, :live_view

  alias Aurora.Assistant
  alias Aurora.Assistant.{ClaudeClient, ContextBuilder, ToolRegistry}

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
     |> assign(:error_message, nil)}
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
  def handle_info(:generate_response, socket) do
    conversation = socket.assigns.current_conversation
    messages = Assistant.get_recent_messages(conversation.id, 20)
    api_messages = Assistant.format_messages_for_api(messages)

    system_prompt = ContextBuilder.build_system_prompt()
    tools = ToolRegistry.all_tools()

    case ClaudeClient.create_message(api_messages, system_prompt: system_prompt, tools: tools) do
      {:ok, response} ->
        handle_api_response(socket, response)

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:is_loading, false)
         |> assign(:error_message, "API Error: #{error}")}
    end
  end

  @impl true
  def handle_info({:continue_with_tool_result, tool_use_id, result}, socket) do
    conversation = socket.assigns.current_conversation
    messages = Assistant.get_recent_messages(conversation.id, 20)
    api_messages = Assistant.format_messages_for_api(messages)

    system_prompt = ContextBuilder.build_system_prompt()
    tools = ToolRegistry.all_tools()

    case ClaudeClient.continue_with_tool_results(api_messages, [{tool_use_id, result}],
           system_prompt: system_prompt,
           tools: tools
         ) do
      {:ok, response} ->
        handle_api_response(socket, response)

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:is_loading, false)
         |> assign(:error_message, "API Error: #{error}")}
    end
  end

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
        assign(socket, :messages, messages)
      else
        socket
      end

    # Handle tool uses
    case tool_uses do
      [] ->
        {:noreply, assign(socket, :is_loading, false)}

      [tool_use | _] ->
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

        <!-- Input Area -->
        <div class="border-t border-primary/20 p-4 bg-base-200">
          <form phx-submit="send_message" class="flex gap-2">
            <input
              type="text"
              name="message"
              value={@input_text}
              placeholder="Ask Aurora anything..."
              class="input input-imperial flex-1"
              disabled={@is_loading}
              autocomplete="off"
              autofocus
            />
            <button
              type="submit"
              class="btn btn-imperial-primary"
              disabled={@is_loading}
            >
              <.icon name="hero-paper-airplane" class="w-5 h-5" />
            </button>
          </form>
          <p class="text-xs text-base-content/40 mt-2 text-center">
            Aurora can manage your tasks, habits, goals, journal, finances, and calendar.
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
