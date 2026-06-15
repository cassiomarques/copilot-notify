.PHONY: build test install release clean

build:
	swift build

test:
	swift test

release:
	swift build -c release

app: release
	chmod +x build.sh
	./build.sh

install: app
	./build.sh --install

clean:
	rm -rf .build dist
