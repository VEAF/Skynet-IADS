# Status vocabulary

One set of five, used identically in `.backlog/README.md` and at the top of every `PRD.md` and
ticket. Same vocabulary as VEAF-Mission-Creation-Tools and CTLD.

| | Status | Meaning |
|---|---|---|
| ⬜ | ready | Specified and unblocked. An agent may pick it up and start. |
| 🔄 | in-progress | Someone is on it. Say who, or which branch. |
| 🧑 | waiting-human | Blocked on a person: a decision, a test in DCS, a credential, an answer. **Say what is expected and from whom** — a waiting-human with no named expectation is a lot nobody will ever unblock. |
| ⏸ | paused | Deliberately parked. Unlike 🧑, nothing is expected of anyone; unlike ⬜, nobody should pick it up. Say what would restart it. |
| ✅ | done | Merged. |
| 🚫 | wontfix | Decided against. **Keep the reasoning** — a wontfix without a reason gets reopened. |

## The distinction that matters

⬜ and ⏸ look alike and are opposites. `ready` invites an agent to start; `paused` tells it not to.
A lot waiting on something that has not shipped yet is **paused**, not ready — and its note should
say what it is waiting for, so nobody has to reconstruct it.

## Blocking

When a lot must not be started — because a decision belongs to someone else, or because starting
would pre-empt a conversation — write the block at the **top of the PRD and of every ticket**, in a
blockquote, naming who is expected to act. A status glyph alone is too easy to skim past, and an
agent that opens a single ticket never sees the PRD.
