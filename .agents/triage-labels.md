# Triage labels: the `Status:` values

Configuration for Pocock's skills. Their triage roles map onto the `Status:` line of a spec as far as
they can:

| Role | Status |
|---|---|
| `needs-info` | `blocked` — the line says what is needed, and from whom |
| `ready-for-agent` | `open` — the spec says an agent may take it |
| `ready-for-human` | `open` — the spec says it needs a person |
| `wontfix` | `dropped` — the line or the spec says why |
| `needs-triage` | none: nothing enters `.tracker/` untriaged; undecided work is in `IDEAS.md` |

`in-progress`, `paused` and `done` have no role.
