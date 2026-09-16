# `omarchy plugin add` clones a repo and expects manifest.json at its root, so a
# monorepo cannot be installed from directly. `git subtree split` solves that:
# each plugin is republished as a thin repo with real history and a root-level
# manifest, which the native installer and `omarchy plugin update` both accept.
#
# The thin repos are build output. Nobody commits to them, so force-pushing is
# the correct operation rather than a destructive one.

PLUGINS := jevido.wiki jevido.clock jevido.media
GH_USER := jevido

.PHONY: publish check link

publish: check
	@for p in $(PLUGINS); do \
	  repo="omarchy-$${p#jevido.}"; \
	  echo "→ $$p → $(GH_USER)/$$repo"; \
	  sha=$$(git subtree split --prefix=plugins/$$p HEAD) || exit 1; \
	  git push --force git@github.com:$(GH_USER)/$$repo.git $$sha:refs/heads/main || exit 1; \
	done
	@echo "published $(words $(PLUGINS)) plugin(s)"

# Refuses to publish a tree the shell itself would reject, and refuses to leak
# anything internal into a public repo.
check:
	@fail=0; \
	for p in $(PLUGINS); do \
	  omarchy-plugin-validate plugins/$$p >/dev/null || { echo "invalid: $$p"; fail=1; }; \
	done; \
	if git grep -InE 'allunited|ol_api_[A-Za-z0-9]' -- . ':!NOTICE' ':!Makefile' >/dev/null 2>&1; then \
	  echo "refusing: internal references found"; \
	  git grep -InE 'allunited|ol_api_[A-Za-z0-9]' -- . ':!NOTICE' ':!Makefile'; \
	  fail=1; \
	fi; \
	test $$fail -eq 0 && echo "checks passed"

# Development install: symlink the working tree into the plugin directory.
link:
	@mkdir -p $(HOME)/.config/omarchy/plugins
	@for p in $(PLUGINS); do \
	  ln -sfn $(CURDIR)/plugins/$$p $(HOME)/.config/omarchy/plugins/$$p; \
	  echo "linked $$p"; \
	done
	@echo "run: omarchy-restart-shell"
