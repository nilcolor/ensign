# A thin front door over scripts/*.sh.
.DEFAULT_GOAL := help
.PHONY: help generate build release share install run test clean

help: ## list targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN { FS = ":.*?## " } { printf "  %-9s %s\n", $$1, $$2 }'

generate: ## generate Ensign.xcodeproj from project.yml
	./scripts/generate.sh

build: ## generate the project and build the debug app
	./scripts/build.sh

release: ## build the release app and check its signature and entitlements
	./scripts/release.sh

share: ## build the release app and zip it to ~/Downloads/Ensign-<git describe>.zip
	./scripts/share.sh

install: ## build the release app, replace /Applications/Ensign.app and launch it
	./scripts/install.sh

run: ## build and launch the debug app (for development, not for daily use)
	./scripts/run.sh

test: ## run the EnsignKit unit tests (no Xcode project needed)
	./scripts/test.sh

clean: ## remove generated project and build artifacts
	rm -rf build Ensign.xcodeproj App/Info.plist App/Ensign.entitlements Packages/EnsignKit/.build
