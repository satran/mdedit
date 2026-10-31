.PHONY: project app run test audit check coverage clean
# Signing: ad hoc by default so it builds anywhere; `make app SIGN=-` is the same, or pass your own identity.
SIGN ?= -
XC = xcodebuild -project MDEdit.xcodeproj -scheme MDEdit -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY="$(SIGN)" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=""

# The Xcode project is generated from project.yml (brew install xcodegen).
project:
	xcodegen generate

# Builds build/MDEdit.app
app: project
	$(XC) -configuration Release build | grep -E "error:|warning: .*Sources|BUILD (SUCCEEDED|FAILED)" || true
	rm -rf build/MDEdit.app && cp -R build/DerivedData/Build/Products/Release/MDEdit.app build/MDEdit.app
	@echo "Built build/MDEdit.app"

run: app
	open build/MDEdit.app

# The whole suite. Exits non-zero on any failure. `make test T=DropTests` or `T=DropTests/testBinderDrop...` runs less.
test:
	@scripts/test.sh $(T)

# Checks on the built app and the project's settings (entitlements, sandbox, no network code paths, ...). Needs `make app` first.
audit:
	@scripts/audit.sh

# Everything to run before trusting a change: build, tests, audit.
check: app test audit

# Line coverage of the last test run, per file.
coverage:
	@xcrun xccov view --report --only-targets build/TestResults.xcresult 2>/dev/null | head -60

clean:
	rm -rf build MDEdit.xcodeproj
