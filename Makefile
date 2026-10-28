.PHONY: build run test release clean adapter

adapter:
	./scripts/build-mediaremote-adapter.sh

build:
	./scripts/build-app.sh debug

release:
	./scripts/build-app.sh release

run: build
	-pkill -x DynamicIsland
	while pgrep -x DynamicIsland >/dev/null; do sleep 0.1; done
	open build/DynamicIsland.app

test:
	swift test

clean:
	rm -rf .build build
