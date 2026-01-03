.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@echo ""
	@echo "Specify a command. The choices are:"
	@echo ""
	@grep -hE '^[0-9a-zA-Z_-]+:.*?## .*$$' ${MAKEFILE_LIST} | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[0;36m%-20s\033[m %s\n", $$1, $$2}'
	@echo ""

.PHONY: lint
lint: ## Run shellcheck
	shellcheck poorman.sh

# .PHONY: unit
# unit: ## Run unit test with shellspec
# 	if type dash; then shellspec -s dash; fi
# 	if type bash; then shellspec -s bash; fi
# 	if type busybox; then shellspec -s 'busybox ash'; fi
# 	if type ksh; then shellspec -s ksh; fi
# 	if type zsh; then shellspec -s zsh; fi

.PHONY: format
format: ## Format code
	shfmt --indent 2 --write *.sh
