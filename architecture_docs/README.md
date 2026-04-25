# Howl Architecture Docs

Family-level architecture authority for cross-repo ownership, dependency direction, and integration flow.

Repo-local architecture details stay in each repo's `app_architecture/`.
This directory is for cross-module fit only.

## Documents

- `MODULE_MAP.md` — module ownership map (responsibility/API/consumes/produces)
- `DEPENDENCY_RULES.md` — allowed and forbidden dependency direction
- `INTEGRATION_FLOW.md` — runtime lifecycle/input/render flow across modules
- `HOWL_HOST_BACKEND_SPLIT.md` — legacy split note (kept for continuity)
