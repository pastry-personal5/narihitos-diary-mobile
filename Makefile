.PHONY: build generate lint open

lint:
	scripts/lint.sh

generate:
	scripts/generate-project.sh

build: generate
	xcodebuild -quiet \
		-project NarihitosDiary.xcodeproj \
		-scheme NarihitosDiary \
		-destination 'generic/platform=iOS Simulator' \
		-derivedDataPath build/DerivedData \
		CODE_SIGNING_ALLOWED=NO \
		build

open: generate
	open -a Xcode NarihitosDiary.xcodeproj
