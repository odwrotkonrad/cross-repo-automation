##[>] 🤖🤖
#[what] Workspace parent Makefile: delegate child-repo targets from any cloned parent dir
#[where] che-linked onto $HOME/projects, $HOME/projects/gitlab, $HOME/projects/gitlab/konradodwrot
#[why] run e.g. `make init-note` or `make notes-render-templates` from a parent dir instead of `make -C konradodwrot/notes <target>`
SHELL := zsh
.SHELLFLAGS := -c

#[what] workspace root: the dir holding konradodwrot/notes, found near $(CURDIR)
#[why] the same file is linked above (~/projects), at (~/projects/gitlab), and below
#   (~/projects/gitlab/konradodwrot) the workspace root; probe $(CURDIR), then its
#   descendants down to the linked depths, then ancestors, first hit wins
ROOT := $(shell c=$(CURDIR); for d in $$c $$c/gitlab $$c/gitlab/konradodwrot $${c:h} $${c:h:h}; do [[ -d $$d/konradodwrot/notes ]] && { print -r -- $$d; break }; done)

#[what] cloned repo paths (workspace-root-relative), discovered from the tree on every run: a moved
#   or new repo appears without a hand edit. A <name>-<target> passthrough uses the path's last
#   segment as <name> (all basenames unique here).
REPOS := $(shell cd $(ROOT) && print -l **/.git(N/:h) | sort)

#[what] resolve a repo name (basename) to its absolute cloned dir under the workspace root
repo_dir = $(ROOT)/$(filter %/$(1) $(1),$(REPOS))

##[>] Passthrough [genai-include]
#[what] <repo>-<target> delegates <target> to that child repo, e.g. `make notes-render-templates`
$(foreach p,$(REPOS),$(eval $(notdir $(p))-%: ; @$$(MAKE) -C $$(call repo_dir,$(notdir $(p))) $$*))
##[<] Passthrough

##[>] Notes [genai-include]
#[what] hot alias: initialize today's dated note in konradodwrot/notes (= notes-init-note)
init-note:
	@$(MAKE) -C $(call repo_dir,notes) init-note
##[<] Notes

##[>] Multi-Repo [genai-include]
#[what] commit in every repo with changes (git-commit-upsert per repo)
commit-all:
	@exec-per-repo.zsh -C $(ROOT) --must-filter=changes git-commit-upsert.zsh

#[what] upsert MRs in every repo (git-mr-upsert per repo; branches off main first when main carries new commits)
mr-all:
	@exec-per-repo.zsh -C $(ROOT) git-mr-upsert.zsh

#[what] full git flow in every repo: commit, branch-name, MR (git-upsert-all per repo; its no-op guard skips untouched repos)
publish-all:
	@exec-per-repo.zsh -C $(ROOT) git-upsert-all.zsh

#[what] MR pipeline snapshot for every repo
pipeline-status-mr-all:
	@exec-per-repo.zsh -C $(ROOT) git-mr-pipeline-status.zsh --no-wait

#[what] latest main pipeline snapshot for every repo
pipeline-status-main-all:
	@exec-per-repo.zsh -C $(ROOT) git-mr-pipeline-status.zsh --no-wait --main
##[<] Multi-Repo

##[>] Sync [genai-include]
#[what] tools-configs convenience sync (= tools-configs-sync)
sync:
	@$(MAKE) -C $(call repo_dir,tools-configs) sync

#[what] tools-configs full sync, scripts included (= tools-configs-sync-full)
sync-full:
	@$(MAKE) -C $(call repo_dir,tools-configs) sync-full
##[<] Sync

.PHONY: init-note commit-all mr-all publish-all pipeline-status-mr-all pipeline-status-main-all sync sync-full
##[<] 🤖🤖
