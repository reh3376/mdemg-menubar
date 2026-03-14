.PHONY: all generate build test clean run setup

all: generate build

generate:
	xcodegen generate

build: generate
	xcodebuild -scheme MdemgMenuBar -configuration Debug build

test: generate
	xcodebuild -scheme MdemgMenuBarTests -configuration Debug test

clean:
	xcodebuild clean 2>/dev/null || true
	rm -rf DerivedData build

run: build
	open "$$(xcodebuild -scheme MdemgMenuBar -configuration Debug -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | awk '{print $$NF}')/MdemgMenuBar.app"

setup:
	@command -v xcodegen >/dev/null 2>&1 || { echo "Installing xcodegen..."; brew install xcodegen; }
	$(MAKE) generate

help:
	@echo "Targets:"
	@echo "  setup    - Install xcodegen and generate project"
	@echo "  generate - Generate Xcode project from project.yml"
	@echo "  build    - Build the app (Debug)"
	@echo "  test     - Run unit tests"
	@echo "  clean    - Remove build artifacts"
	@echo "  run      - Build and launch the app"
