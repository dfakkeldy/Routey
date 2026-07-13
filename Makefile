.PHONY: devlog-update devlog-pr-body doc-automation-test

devlog-update: ## Update generated weekly devlog blocks from the previous calendar week
	@PYTHONPATH=Scripts python3 -m doc_automation.devlog \
		--markdown docs/guides/devlog.md \
		--html devlog.html \
		--repo-url https://github.com/dfakkeldy/Routey

devlog-pr-body: ## Generate the review checklist and AI-assisted draft for the weekly devlog PR
	@PYTHONPATH=Scripts python3 -m doc_automation.curate_devlog \
		--project-name Routey \
		--markdown docs/guides/devlog.md \
		--html devlog.html \
		--repo-url https://github.com/dfakkeldy/Routey \
		--extra-guidance "Routey is an offline-first rural delivery workflow app. Keep copy carrier-agnostic and never include real route data, real street or site names, employer names, civic numbers, or carrier-specific jargon." \
		--extra-checklist "No real route data, street names, site names, employer names, civic numbers, or carrier-specific jargon." \
		--out "$${DEVLOG_PR_BODY:-devlog-pr-body.md}"

doc-automation-test: ## Run the doc-automation Python unit tests
	@PYTHONPATH=Scripts python3 -m unittest discover -s Scripts/doc_automation/tests -t Scripts -v
