##[>] 🤖🤖
#[what] Project's Makefile
SHELL := zsh

WRAPPERS := repo-prepare-dev-env
COMMANDS := semver-next tag-mint aggregate aggregate-check dispatch test repo-ci-prepare-hooks repo-ci-precommit-all

#[why] render-templates, repo-ci-render-templates and repo-render-env are declared .PHONY by the shared .mk, never here: a .PHONY name make cannot build reports "nothing to be done" and exits 0, turning a failed bootstrap into a silent success
.PHONY: $(WRAPPERS) $(COMMANDS)

##[>] Dev Environment [genai-include]
#[why] render precedes hooks: the docsgen pre-commit hook runs render-templates and fails on drift,
#   so a fresh clone whose generated files were never rendered would fail its first commit
#[what] make a fresh clone a working checkout: generated docs, git hooks
repo-prepare-dev-env: repo-render-env render-templates repo-ci-prepare-hooks
##[<] Dev Environment

##[>] Docs [genai-include]
#[what] shared render targets, authored in cross-repo/misc and rendered here by the bootstrap rule below
-include shared/ci/make/render.mk

#[why] gitignored shared/ tree: a fresh clone has no render.mk, so make renders it, then re-execs itself with the shared targets defined
#[why] CI carries every ref as a job variable and has no glab auth: seed .env only when the environment names no MISC_REF
shared/ci/make/render.mk:
	@[[ -n $${MISC_REF:-} ]] || CHE_ENV_UNSET=empty $${CHE_BIN:-che} render-templates --profiles=envSeed
	@$${CHE_BIN:-che} render-templates --profiles=bootstrapCrossRepoCI
##[<] Docs

##[>] Graph [genai-include]
#[what] aggregate per-repo .repo/ declarations into the four generated system graph files
aggregate:
	@bin/automation aggregate

#[what] fail if any generated system graph file drifted from the aggregated declarations
aggregate-check:
	@bin/automation aggregate --check
##[<] Graph

##[>] Events [genai-include]
#[what] turn AUTOMATION_EVENT (or EVENT_FILE=<json>) into the regen child pipeline at EMIT (default regen-pipeline.yml)
dispatch:
	@bin/automation dispatch $(if $(EVENT_FILE),--event-file $(EVENT_FILE)) --emit $(or $(EMIT),regen-pipeline.yml)

#[what] run the dispatcher's minitest suite
test:
	@ruby -Ilib -e 'Dir.glob("test/**/*_test.rb").sort.each { |f| require File.expand_path(f) }'
##[<] Events

##[>] Release [genai-include]
#[what] print the next semver tag inferred from the last tag..HEAD diff (override: `semver: major|minor|patch` commit token)
semver-next: render-templates
	@shared/ci/semver-bump.zsh

#[what] mint and push the next semver tag (CI: authed via TAG_TOKEN)
tag-mint: render-templates
	@shared/ci/tag-mint.zsh
##[<] Release

##[>] CI [genai-include]
#[what] install lefthook git hooks
repo-ci-prepare-hooks:
	@lefthook install --force

#[what] run pre-commit hooks over all files (not just staged)
repo-ci-precommit-all: repo-ci-prepare-hooks
	@lefthook run pre-commit --all-files --force
##[<] CI
##[<] 🤖🤖
