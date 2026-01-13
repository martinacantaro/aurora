defmodule AuroraWeb.BoardLive.Index do
  use AuroraWeb, :live_view

  alias Aurora.Boards
  alias Aurora.Boards.Board

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Operations Command")
     |> assign(:show_new_form, false)
     |> stream(:boards, Boards.list_boards())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New War Room")
    |> assign(:show_new_form, true)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Operations Command")
    |> assign(:show_new_form, false)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    board = Boards.get_board!(id)
    {:ok, _} = Boards.delete_board(board)
    {:noreply, stream_delete(socket, :boards, board)}
  end

  def handle_event("show_new", _params, socket) do
    {:noreply, assign(socket, :show_new_form, true)}
  end

  def handle_event("cancel_new", _params, socket) do
    {:noreply, assign(socket, :show_new_form, false)}
  end

  @impl true
  def handle_event("save", %{"name" => name}, socket) do
    case Boards.create_board(%{name: name}) do
      {:ok, board} ->
        {:noreply,
         socket
         |> stream_insert(:boards, board)
         |> assign(:show_new_form, false)
         |> put_flash(:info, "War room established!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create board")}
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
                <.icon name="hero-view-columns" class="w-6 h-6 text-primary" />
                <h1 class="text-2xl tracking-wider text-primary">Operations Command</h1>
              </div>
            </div>
            <button phx-click="show_new" class="btn btn-imperial-primary btn-sm">
              <.icon name="hero-plus" class="w-4 h-4" />
              New War Room
            </button>
          </div>
        </div>
      </header>

      <main class="container mx-auto px-4 py-6 pb-24">
        <!-- New Board Form -->
        <%= if @show_new_form do %>
          <div class="card card-ornate corner-tl corner-tr corner-bl corner-br mb-6 p-4">
            <h2 class="panel-header">Establish War Room</h2>
            <form phx-submit="save" class="space-y-4">
              <div class="form-control">
                <label class="label"><span class="stat-block-label">Operation Name</span></label>
                <input type="text" name="name" class="input input-imperial" required autofocus placeholder="Enter operation designation..." />
              </div>
              <div class="flex gap-2 justify-end">
                <button type="button" phx-click="cancel_new" class="btn btn-imperial">Cancel</button>
                <button type="submit" class="btn btn-imperial-primary">Establish</button>
              </div>
            </form>
          </div>
        <% end %>

        <!-- Boards Grid -->
        <%= if Enum.empty?(@streams.boards |> Enum.to_list()) do %>
          <div class="card card-ornate corner-tl corner-tr corner-bl corner-br p-8 text-center">
            <p class="text-base-content/50 italic">No operations established. Create a war room to coordinate your campaigns.</p>
          </div>
        <% else %>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6" id="boards" phx-update="stream">
            <div :for={{dom_id, board} <- @streams.boards} id={dom_id} class="card card-ornate corner-tl corner-br p-4 hover:border-primary/60 transition-colors">
              <div class="flex items-center gap-3 mb-4">
                <.icon name="hero-map" class="w-5 h-5 text-primary" />
                <h2 class="text-lg font-semibold text-primary"><%= board.name %></h2>
              </div>
              <div class="flex gap-2 justify-end">
                <.link navigate={~p"/boards/#{board.id}"} class="btn btn-imperial-primary btn-sm">
                  <.icon name="hero-arrow-right" class="w-4 h-4" />
                  Enter
                </.link>
                <button phx-click="delete" phx-value-id={board.id} data-confirm="Abandon this operation?" class="btn btn-imperial-danger btn-sm">
                  <.icon name="hero-trash" class="w-4 h-4" />
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </main>

      <!-- HUD Navigation -->
      <nav class="fixed bottom-0 left-0 right-0 hud-nav">
        <.link navigate={~p"/boards"} class="hud-nav-item hud-nav-item-active">
          <.icon name="hero-view-columns" class="hud-nav-icon" />
          <span class="hud-nav-label">Operations</span>
        </.link>
        <.link navigate={~p"/goals"} class="hud-nav-item">
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
end
