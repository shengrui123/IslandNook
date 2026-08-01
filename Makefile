.PHONY: build debug app run clean

build:
	env CLANG_MODULE_CACHE_PATH="$(CURDIR)/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$(CURDIR)/.build/swiftpm-cache" swift build -c release --disable-sandbox -debug-info-format none

debug:
	env CLANG_MODULE_CACHE_PATH="$(CURDIR)/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$(CURDIR)/.build/swiftpm-cache" swift build --disable-sandbox

app:
	chmod +x scripts/build-app.sh
	./scripts/build-app.sh release

run: app
	open dist/IslandNook.app

clean:
	swift package clean
