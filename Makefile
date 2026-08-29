##[>] 🤖🤖
SHELL := zsh

COMMANDS := che-install generic-setup aggregate aggregate-check dispatch test

.PHONY: $(COMMANDS)

-include shared/generic/make/generic.mk

##[>] Setup [genai-include]
#[what] install the latest released che into ~/.local/bin, only when the one on PATH is older
che-install:
	@curl -fsSL https://konradodwrot.gitlab.io/go-modules/che-install.sh | sh -s -- --skip-if-present-is-newer

#[what] render the generic consumer payload (generic.mk, lefthook.yml, shared/generic/) at the pinned CENTRALIZED_ASSETS_GENERIC_REF
generic-setup:
	@$${CHE_BIN:-che} render-templates --profiles=genericSetup

shared/generic/make/generic.mk: generic-setup
##[<] Setup

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
##[<] 🤖🤖
