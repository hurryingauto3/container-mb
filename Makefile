.PHONY: build test run package clean

build:
	swift build

test:
	swift run ContainerCoreSmokeTests

run:
	swift run ContainerMenuBar

package:
	Scripts/package-app.sh

clean:
	rm -rf .build dist ContainerMenuBar.app
