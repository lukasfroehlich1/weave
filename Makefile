GHOSTTY_DIR = vendor/ghostty
GHOSTTY_XCFRAMEWORK = $(GHOSTTY_DIR)/macos/GhosttyKit.xcframework

.PHONY: all ghostty app clean

all: ghostty app

ghostty: $(GHOSTTY_XCFRAMEWORK)

$(GHOSTTY_XCFRAMEWORK):
	cd $(GHOSTTY_DIR) && zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast

app: $(GHOSTTY_XCFRAMEWORK)
	xcodebuild -project Weave.xcodeproj -scheme Weave -configuration Debug build

clean:
	rm -rf build
