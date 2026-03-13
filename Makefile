GHOSTTY_DIR = vendor/ghostty
XCFRAMEWORK = GhosttyKit.xcframework
GHOSTTY_XCFRAMEWORK = $(GHOSTTY_DIR)/macos/$(XCFRAMEWORK)

.PHONY: all ghostty app clean

all: ghostty app

ghostty: $(XCFRAMEWORK)

$(XCFRAMEWORK): $(GHOSTTY_XCFRAMEWORK)
	ln -sfn $(GHOSTTY_XCFRAMEWORK) $(XCFRAMEWORK)

$(GHOSTTY_XCFRAMEWORK):
	cd $(GHOSTTY_DIR) && zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast

app: $(XCFRAMEWORK)
	xcodebuild -project Weave.xcodeproj -scheme Weave -configuration Debug build

clean:
	rm -rf build
	rm -f $(XCFRAMEWORK)
