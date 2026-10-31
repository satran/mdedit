.PHONY: project app run test clean
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

test: project
	$(XC) -configuration Debug test | grep -E "error:|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)|✘|failed" || true

clean:
	rm -rf build MDEdit.xcodeproj
