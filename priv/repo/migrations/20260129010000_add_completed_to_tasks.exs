defmodule Aurora.Repo.Migrations.AddCompletedToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :completed, :boolean, default: false, null: false
      add :completed_at, :utc_datetime
    end
  end
end
