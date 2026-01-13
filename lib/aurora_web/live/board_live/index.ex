defmodule AuroraWeb.BoardLive.Index do
  use AuroraWeb, :live_view

  alias Aurora.Boards
  alias Aurora.Boards.Board

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Boards")
     |> assign(:show_new_form, false)
     |> stream(:boards, Boards.list_boards())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Board")
    |> assign(:show_new_form, true)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Boards")
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
         |> put_flash(:info, "Board created successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create board")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="flex justify-between items-center mb-8">
        <div class="flex items-center gap-4">
          <.link navigate={~p"/"} class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="w-4 h-4" />
          </.link>
          <h1 class="text-3xl font-bold">Boards</h1>
        </div>
        <button phx-click="show_new" class="btn btn-primary">
          <.icon name="hero-plus" class="w-4 h-4" />
          New Board
        </button>
      </div>

      <!-- New Board Form -->
      <%= if @show_new_form do %>
        <div class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title">New Board</h2>
            <form phx-submit="save" class="space-y-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Board Name</span></label>
                <input type="text" name="name" class="input input-bordered" required autofocus />
              </div>
              <div class="flex gap-2 justify-end">
                <button type="button" phx-click="cancel_new" class="btn btn-ghost">Cancel</button>
                <button type="submit" class="btn btn-primary">Create Board</button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6" id="boards" phx-update="stream">
        <div :for={{dom_id, board} <- @streams.boards} id={dom_id} class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
          <div class="card-body">
            <h2 class="card-title"><%= board.name %></h2>
            <div class="card-actions justify-end mt-4">
              <.link navigate={~p"/boards/#{board.id}"} class="btn btn-primary btn-sm">
                Open
              </.link>
              <button phx-click="delete" phx-value-id={board.id} data-confirm="Are you sure?" class="btn btn-ghost btn-sm text-error">
                <.icon name="hero-trash" class="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
