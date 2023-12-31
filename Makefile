DESTDIR =
PREFIX ?= /usr/local
BUILD_TYPE ?= Release
BUILD_DIR := build

BIN_DIR := $(DESTDIR)$(PREFIX)/bin/
CMAKE_CACHE := $(BUILD_DIR)/CMakeCache.txt \
			   $(BUILD_DIR)/Makefile \
			   $(BUILD_DIR)/compile_commands.json

GIT_SOURCES := git ls-files -- "*.?pp"
SOURCES := $(shell $(GIT_SOURCES))

CHECK_BUILD_TYPE := $(BUILD_DIR)/BUILD.$(BUILD_TYPE)
CHECK_FORMAT := $(BUILD_DIR)/FORMAT

.PHONY: default
default: $(BUILD_DIR)/cgen ## Build cgen

$(CHECK_BUILD_TYPE):
	$(RM) "$(BUILD_DIR)"/BUILD.*
	mkdir -p "$(BUILD_DIR)"
	touch "$@"

$(CMAKE_CACHE): CMakeLists.txt $(CHECK_BUILD_TYPE) $(CHECK_FORMAT)
	cmake \
		-S . \
		-B "$(BUILD_DIR)" \
		-G "Unix Makefiles" \
		-D CMAKE_BUILD_TYPE="$(BUILD_TYPE)" \
		-D CMAKE_EXPORT_COMPILE_COMMANDS=ON

$(BUILD_DIR)/cgen: $(CMAKE_CACHE) $(SOURCES)
	cmake \
		--build "$(BUILD_DIR)" \
		--config "$(BUILD_TYPE)" \
		--target cgen \
		--parallel

$(BUILD_DIR)/libcgen_test: $(CMAKE_CACHE) $(SOURCES)
	cmake \
		--build "$(BUILD_DIR)" \
		--config "$(BUILD_TYPE)" \
		--target libcgen_test \
		--parallel

# Helpers

.PHONY: clean
clean: ## Remove $(BUILD_DIR)
	$(RM) -r "$(BUILD_DIR)"

.PHONY: install
install: ## Install cgen into $(DESTDIR)$(PREFIX)/bin (/usr/local/bin by default)
	strip "$(BUILD_DIR)/cgen"
	install -d "$(BIN_DIR)"
	install -m 755 "$(BUILD_DIR)/cgen" "$(BIN_DIR)"

.PHONY: run
run: $(BUILD_DIR)/cgen ## Run cgen executable
	"./$(BUILD_DIR)/cgen"

.PHONY: test
test: export BUILD_TYPE=Debug
test: $(BUILD_DIR)/libcgen_test ## Run test executable
	"./$(BUILD_DIR)/libcgen_test"

# Compilers

.PHONY: clang
clang: export CC=clang
clang: export CXX=clang++
clang: clean $(CMAKE_CACHE) ## Configure with Clang compiler

.PHONY: gcc
gcc: export CC=gcc
gcc: export CXX=g++
gcc: clean $(CMAKE_CACHE) ## Configure with GCC compiler

# Format

.PHONY: format
format: $(CHECK_FORMAT) ## Format source code using `clang-format`

$(CHECK_FORMAT): $(SOURCES)
	$(GIT_SOURCES) | xargs clang-format -i --style=file
	touch "$@"

.PHONY: ci
ci: ## Run all CI stages locally
	$(MAKE) lint
	$(MAKE) sanitize
	$(MAKE) BUILD_TYPE=Debug test
	$(MAKE) BUILD_TYPE=Release test

# Linting

.PHONY: lint
lint: ## Run all linters
	$(MAKE) lint/cppcheck
	$(MAKE) lint/clang-tidy
	$(MAKE) lint/codespell

.PHONY: lint/cppcheck
lint/cppcheck: $(CMAKE_CACHE) ## Run `cppcheck`
	cppcheck \
		--cppcheck-build-dir="$(BUILD_DIR)" \
		--check-level=exhaustive \
		--error-exitcode=1 \
		--enable=all \
		--language=c++ \
		--std=c++20 \
		--inline-suppr \
		--suppress=unmatchedSuppression \
		--suppress=missingInclude \
		--suppress=missingIncludeSystem \
		--suppress=unusedStructMember \
		--suppress=unusedFunction \
		--suppress=useStlAlgorithm \
		`$(GIT_SOURCES)`

.PHONY: lint/clang-tidy
lint/clang-tidy: $(CMAKE_CACHE) ## Run `clang-tidy`
	clang-tidy \
		-p="$(BUILD_DIR)" \
		--warnings-as-errors=* \
		`$(GIT_SOURCES)`

.PHONY: lint/codespell
lint/codespell: ## Check spelling using `codespell`
	codespell \
		-L poost \
		`git ls-files -- "*.md" "*.txt" "*.json" "*.yml" "Makefile"` \
		`$(GIT_SOURCES)`

# Sanitizers

.PHONY: sanitize
sanitize: ## Run all sanitizers on test executable
	$(MAKE) sanitize/asan
	$(MAKE) sanitize/ubsan

.PHONY: sanitize/asan
sanitize/asan: ## Run address sanitizer on test executable
	$(MAKE) BUILD_TYPE=Asan ASAN_OPTIONS=detect_container_overflow=0 test

.PHONY: sanitize/ubsan
sanitize/ubsan: ## Run undefined behavior sanitizer on test executable
	$(MAKE) BUILD_TYPE=Ubsan test

# Tree

.PHONY: tree
tree: ## Show project structure using `tree`
	tree --gitignore -I external

# Todo

.PHONY: todo
todo: ## Show TODOs
	grep --color '\btodo\b' `$(GIT_SOURCES)`

# Help

help: ## Show this help
	@echo
	@echo 'Targets:'
	@echo
	@grep -Eh '\s##\s' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":[^:]*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
	@echo
	@echo 'Default environment:'
	@echo
	@sed -e '/^$$/,$$d' $(MAKEFILE_LIST) | sed -e 's/^/  /'
