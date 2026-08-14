set export

PN := "pnpm"
PNR := PN + " run"

alias z := zed
alias fmt := format

# Update this from `xcrun simctl list devices available` when the simulator changes.
SWIFT_IOS_TEST_DESTINATION := "platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5"

# List available commands
default:
    just --list --unsorted

# Generate the shared UI string catalog, then run all verification checks.
ready: prepare-ready ready-tasks

# Publish node
publish-node:
    {{ PN }} release

# Run all quality checks
[parallel]
quality: format-check lint typecheck

# Run all quality checks for node.js
quality-node: prepare-node quality-node-tasks

# Run all quality checks for swift
quality-swift: lint-swift

# Generate the English source catalog for the shared authentication UI.
generate-localizations:
    xcrun xcstringstool extract \
        --modern-localizable-strings \
        --SwiftUI \
        --output-format xcstrings \
        --output-directory Sources/KamaalAuthUI \
        $(rg --files Sources/KamaalAuthUI -g '*.swift')

# Run all tests on macOS and iOS
[parallel]
test: test-node test-swift

# Run the npm package tests
test-node: prepare-node
    {{ PNR }} test

# Run Swift package tests on macOS and iOS
test-swift: test-swift-macos test-swift-ios

# Run Swift package tests on macOS
test-swift-macos:
    #!/usr/bin/env zsh

    if sw_vers -productVersion | grep -q '^27\.'
    then
        swift test -Xswiftc -warnings-as-errors
    else
        swift test --skip 'AuthSignInScreenSnapshotTests' -Xswiftc -warnings-as-errors
    fi

# Run Swift package tests on iOS
test-swift-ios:
    ./scripts/with-ios-simulator-lock \
        -scheme KamaalAuth-Package \
        -destination "{{ SWIFT_IOS_TEST_DESTINATION }}" \
        test

# Typecheck the npm packages
typecheck: typecheck-node

# Typecheck the npm packages
typecheck-node:
    {{ PNR }} typecheck

# Build the npm packages, in dependency order
build-node:
    {{ PNR }} build

# Build the Swift package
build-swift:
    swift build

# Lint all code
[parallel]
lint: lint-node lint-swift

# Lint js code
lint-node:
    {{ PNR }} lint

# Check Swift code formatting and linting
lint-swift:
    swift format lint --strict -r Sources Tests

# Fix fixable linting errors
lint-fix:
    {{ PNR }} lint:fix

# Check code formatting
format-check: format-check-node

# Check js code formatting
format-check-node:
    {{ PNR }} fmt:check

# Format code
[parallel]
format: format-node format-swift

# Format js code
format-node:
    {{ PNR }} fmt

# Format Swift code
format-swift:
    swift format --in-place -r Sources Tests

# Bootstrap project
bootstrap: prepare

# Prepare project to work with
prepare: prepare-node

# Prepare node.js
prepare-node: install-modules-node build-node

# Install all modules
install-modules: install-modules-node

# Install node modules
install-modules-node:
    {{ PN }} i

# Open project in zed
zed:
    zed .

# Open project in vscode
code:
    code .

# Open the Swift package in Xcode
xcode:
    open Package.swift

[private]
[parallel]
prepare-ready: generate-localizations prepare-node

[private]
[parallel]
ready-tasks: quality test

[private]
[parallel]
quality-node-tasks: typecheck-node lint-node format-check-node
