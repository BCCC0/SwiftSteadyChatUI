SHELL := /bin/bash

.DEFAULT_GOAL := help

IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17
PACKAGE_SCHEME := SwiftSteadyChatUI
SAMPLE_DIR := Examples/SwiftSteadyChatUISample
SAMPLE_SPEC := $(SAMPLE_DIR)/project.yml
SAMPLE_PROJECT := $(SAMPLE_DIR)/SwiftSteadyChatUISample.xcodeproj
SAMPLE_SCHEME := SwiftSteadyChatUISample
XCODEGEN ?= xcodegen

.PHONY: help
help: ## Show available targets.
	@grep -E '^[a-zA-Z0-9_.-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-24s %s\n", $$1, $$2}'

.PHONY: resolve
resolve: ## Resolve Swift package dependencies.
	@swift package resolve

.PHONY: generate-sample-project
generate-sample-project: ## Generate the sample app Xcode project.
	@command -v "$(XCODEGEN)" >/dev/null || { echo "error: xcodegen not found. Install it with 'brew install xcodegen'."; exit 1; }
	@"$(XCODEGEN)" generate --spec "$(SAMPLE_SPEC)" --project "$(SAMPLE_DIR)"

.PHONY: build-sample
build-sample: generate-sample-project ## Generate and build the sample app.
	@xcodebuild build \
		-project "$(SAMPLE_PROJECT)" \
		-scheme "$(SAMPLE_SCHEME)" \
		-configuration Debug \
		-destination "$(IOS_DESTINATION)" \
		-skipMacroValidation \
		CODE_SIGNING_ALLOWED=NO

.PHONY: test
test: ## Run package unit tests.
	@swift test

.PHONY: clean
clean: ## Remove local SwiftPM build products.
	@rm -rf .build
	@rm -rf "$(SAMPLE_PROJECT)"
