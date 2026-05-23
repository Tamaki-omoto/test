# CLAUDE.md

Guidance for AI assistants (Claude Code and others) working in this repository.

## Repository status

This repository is currently **empty** — no source files, no commits on the default branch, no build configuration. This document is a placeholder scaffold; expand each section below as real code is added.

## Remote

- `origin` → `tamaki-omoto/test` on GitHub.

## Branching

- Claude-authored work lives on branches named `claude/<short-description>-<suffix>` (e.g. `claude/add-claude-documentation-iz3ki`).
- Create the branch locally if it does not exist, develop on it, and push with:
  ```
  git push -u origin <branch-name>
  ```
- Do **not** push directly to the default branch.

## Commits

- Write clear, descriptive commit messages explaining the *why* of the change.
- Prefer creating a **new** commit over amending an existing one, especially after a pre-commit hook failure (the failed commit did not happen, so `--amend` would rewrite the previous commit).
- Never use `--no-verify` or other hook-skipping flags unless the user explicitly asks.

## Pull requests

- Do **not** open a pull request unless the user explicitly asks for one.
- When asked, use the GitHub MCP tools (`mcp__github__create_pull_request`, etc.). The `gh` CLI is not available in this environment.

## GitHub access

- GitHub interactions go through the `mcp__github__*` MCP tools.
- Tool scope is restricted to the `tamaki-omoto/test` repository.

## Sections to fill in as the codebase grows

- **Project overview** — what this repo is, who uses it, the high-level architecture.
- **Build / test / lint commands** — exact commands an assistant should run before reporting a task complete.
- **Directory layout** — top-level folders and what belongs in each.
- **Key conventions** — naming, formatting, error-handling patterns, comment policy.
- **Testing strategy** — frameworks, where tests live, how to run a single test.
- **Dependencies** — package manager, lockfile policy, version pinning rules.
