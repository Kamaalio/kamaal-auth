set export

PN := "pnpm"
PNR := PN + " run"
PNX := PN + " exec"

alias z := zed
alias fmt := format
alias fmt-c := format-check
alias prep := prepare
alias i := install-modules

# List available commands
default:
    just --list --unsorted

# Run all verification checks
[parallel]
ready: quality test

# Run all quality checks
[parallel]
quality: format-check lint typecheck

# Run all tests
[parallel]
test: test-ts test-swift

# Run server package tests
[working-directory("server")]
test-ts:
    {{ PNR }} test

# Run Swift package tests
test-swift:
    swift test

# Typecheck the server package
[working-directory("server")]
typecheck:
    {{ PNR }} typecheck

# Build the server package
[working-directory("server")]
build-ts:
    {{ PNR }} build

# Build the Swift package
build-swift:
    swift build

# Lint js code
lint:
    {{ PNR }} lint

# Fix fixable linting errors
lint-fix:
    {{ PNR }} lint:fix

# Check code formatting
[parallel]
format-check: format-check-ts format-check-swift

# Check js code formatting
format-check-ts:
    {{ PNR }} fmt:check

# Check Swift code formatting
format-check-swift:
    swift format lint --strict -r Sources Tests

# Format code
[parallel]
format: format-ts format-swift

# Format js code
format-ts:
    {{ PNR }} fmt

# Format Swift code
format-swift:
    swift format --in-place -r Sources Tests

# Bootstrap project
bootstrap: prepare

# Prepare project to work with
prepare: install-modules

# Install all modules
install-modules:
    {{ PN }} i

# Tag and push an npm release, e.g. `just release-npm 0.1.0`
release-npm version: ready
    git tag "npm/{{ version }}"
    git push origin "npm/{{ version }}"

# Tag and push a Swift package release, e.g. `just release-spm 0.1.0`
release-spm version: ready
    git tag "{{ version }}"
    git push origin "{{ version }}"

# Open project in zed
zed:
    zed .

# Open project in vscode
code:
    code .

# Open the Swift package in Xcode
xcode:
    open Package.swift
