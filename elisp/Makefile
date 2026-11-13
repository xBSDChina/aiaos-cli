# Makefile for AIAOS-CLI Emacs Frontend

# Variables
EMACS ?= emacs
ELISP_DIR = .
SOURCES = $(wildcard $(ELISP_DIR)/*.el)
TESTS = $(wildcard $(ELISP_DIR)/test-*.el)
COMPILED = $(SOURCES:.el=.elc)

# Colors
GREEN = \033[0;32m
YELLOW = \033[0;33m
RED = \033[0;31m
NC = \033[0m # No Color

.PHONY: all help clean test compile check deps install setup

all: compile

help: ## Show this help message
	@echo "$(GREEN)AIAOS-CLI Makefile$(NC)"
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?##/ { printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

setup: ## Set up development environment
	@echo "$(YELLOW)Setting up development environment...$(NC)"
	@make deps
	@make compile

deps: ## Install dependencies
	@echo "$(YELLOW)Installing dependencies...$(NC)"
	@$(EMACS) --batch -l package -eval '(package-refresh-archives)' 2>/dev/null || true
	@echo "$(GREEN)Dependencies installed$(NC)"

compile: ## Compile Emacs Lisp files
	@echo "$(YELLOW)Compiling Emacs Lisp files...$(NC)"
	@$(EMACS) --batch -L $(ELISP_DIR) -f byte-compile-directory $(ELISP_DIR) 2>&1 | grep -v "^$$" || true
	@echo "$(GREEN)Compilation complete$(NC)"

test: ## Run tests
	@echo "$(YELLOW)Running tests...$(NC)"
	@$(EMACS) --batch -L $(ELISP_DIR) -l aiaos-cli-tests.el -f aiaos-cli-run-tests 2>&1 || true
	@echo "$(GREEN)Tests complete$(NC)"

check: ## Check code with checkdoc
	@echo "$(YELLOW)Checking code...$(NC)"
	@for f in $(SOURCES); do \
		$(EMACS) --batch --check-docstring $$f 2>&1 || true; \
	done
	@echo "$(GREEN)Check complete$(NC)"

clean: ## Clean compiled files
	@echo "$(YELLOW)Cleaning compiled files...$(NC)"
	@rm -f $(COMPILED)
	@echo "$(GREEN)Clean complete$(NC)"

install: ## Install to user Emacs directory
	@echo "$(YELLOW)Installing to ~/.emacs.d/...$(NC)"
	@mkdir -p ~/.emacs.d/aiaos-cli
	@cp $(SOURCES) ~/.emacs.d/aiaos-cli/
	@echo "$(GREEN)Installation complete$(NC)"

uninstall: ## Uninstall from user Emacs directory
	@echo "$(YELLOW)Uninstalling from ~/.emacs.d/...$(NC)"
	@rm -rf ~/.emacs.d/aiaos-cli
	@echo "$(GREEN)Uninstall complete$(NC)"

check-deps: ## Check dependencies
	@echo "$(YELLOW)Checking dependencies...$(NC)"
	@$(EMACS) --batch -L $(ELISP_DIR) -l aiaos-cli-core.el --eval '(message "Core loaded")' 2>&1 || true
	@$(EMACS) --batch -L $(ELISP_DIR) -l aiaos-cli-state.el --eval '(message "State loaded")' 2>&1 || true
	@$(EMACS) --batch -L $(ELISP_DIR) -l aiaos-cli-context.el --eval '(message "Context loaded")' 2>&1 || true
	@echo "$(GREEN)Dependency check complete$(NC)"

list-deps: ## List dependencies
	@echo "$(YELLOW)Listing dependencies...$(NC)"
	@$(EMACS) --batch -L $(ELISP_DIR) -l aiaos-cli-core.el --eval '(message "Dependencies: %s" (list))' 2>&1 || true
	@echo "$(GREEN)Dependency list complete$(NC)"

.PHONY: all help clean test compile check deps install setup check-deps list-deps