.PHONY: generate open clean archive upload

SCHEME     = EVRoutePlan
ARCHIVE    = build/EVRoutePlan.xcarchive
EXPORT_DIR = build/export

generate:
	xcodegen generate

open: generate
	open EVRoutePlan.xcodeproj

clean:
	rm -rf EVRoutePlan.xcodeproj build/

archive: generate
	xcodebuild archive \
		-scheme $(SCHEME) \
		-archivePath $(ARCHIVE) \
		-allowProvisioningUpdates \
		| xcpretty

upload: archive
	xcodebuild -exportArchive \
		-archivePath $(ARCHIVE) \
		-exportPath $(EXPORT_DIR) \
		-exportOptionsPlist ExportOptions.plist \
		-allowProvisioningUpdates \
		| xcpretty
