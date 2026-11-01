# A stress scenario for the in-sim suite

Status: open

## The problem

`skynet-test-persian-gulf-stress-test.miz` puts the Persian Gulf demo's network under many more sites.
It is a test, not a demo, and it leaves `demo-missions/` with
`chore-demo-missions-carry-their-script`, which moves it into this folder.

## The target

An in-sim scenario, in `test/insim/`, that measures what the stress mission was for: Skynet's behaviour
with a large network. Until then the `.miz` here is a reference for its layout. It holds placeholders
instead of its scripts; its setup script was `demo-missions/skynet-iads-setup-persian-gulf.lua`.

## Open

- What the scenario measures, and what counts as passing.
- Whether it runs in the `full` tier, or on demand only.
