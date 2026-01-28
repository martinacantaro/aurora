# Aurora

A personal productivity dashboard built with Elixir, Phoenix LiveView, and DaisyUI. Track your tasks, habits, and goals in one place.

## Features

### Kanban Boards
- Drag-and-drop task management
- Multiple boards and columns
- Task labels with custom colors
- Priority levels (P1-P4) with visual indicators
- Due dates with overdue highlighting
- Filter by label, priority, due date, or search

### Habit Tracking
- Daily habit tracking with one-click completion
- Streak tracking
- Flexible scheduling (daily, weekly, specific days)
- Time of day preferences

### Goal Management
- Hierarchical goals (nest sub-goals under parent goals)
- Multiple timeframes: Daily, Weekly, Monthly, Quarterly, Yearly, Multi-Year
- Categories: Health, Career, Relationships, Finance, Personal Growth
- Progress tracking with visual indicators

### Dashboard
- Overview of all your boards, habits, and goals
- Quick stats and progress at a glance

## Tech Stack

- **Backend**: Elixir + Phoenix Framework 1.8
- **Frontend**: Phoenix LiveView + DaisyUI (Tailwind CSS)
- **Database**: PostgreSQL
- **Real-time**: LiveView WebSockets

## Getting Started

### Prerequisites

- Elixir 1.17+
- Erlang 27+
- PostgreSQL 14+
- Node.js 18+ (for asset compilation)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/martinacantaro/aurora.git
   cd aurora
   ```

2. Install dependencies and set up the database:
   ```bash
   make setup
   ```

3. Configure your database in `config/dev.exs` if needed (defaults to your system username)

4. Create a `.env` file for your environment variables (this file is gitignored):
   ```bash
   echo 'export ANTHROPIC_API_KEY=your-key-here' > .env
   ```

5. Start the server:
   ```bash
   make server
   ```

6. Visit [localhost:4001](http://localhost:4001)

### Make Commands

The Makefile automatically loads your `.env` file. Available commands:

| Command | Description |
|---------|-------------|
| `make server` | Start the Phoenix server on port 4001 |
| `make console` | Start server with interactive IEx shell |
| `make deps` | Install dependencies |
| `make setup` | Full setup (deps + database) |
| `make db.migrate` | Run database migrations |
| `make db.reset` | Reset the database |
| `make test` | Run tests |

### Default Login

The app uses simple password authentication. Default password in development: `aurora`

## Data Backup

Your data is stored in PostgreSQL. Backup scripts are included:

```bash
# Create a backup
./scripts/backup.sh

# Restore from a backup
./scripts/restore.sh backups/aurora_backup_YYYYMMDD_HHMMSS.sql.gz
```

Backups are stored in the `backups/` folder (gitignored).

**Tip**: Set `AURORA_CLOUD_BACKUP_DIR` to automatically copy backups to a cloud-synced folder:
```bash
export AURORA_CLOUD_BACKUP_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Backups/Aurora"
```

## Roadmap

- [ ] Journaling with AI-prompted reflections
- [ ] Financial tracking
- [ ] AI coaching integration (Claude API)
- [ ] Mobile-responsive improvements
- [ ] Data export (JSON/CSV)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) for details.
