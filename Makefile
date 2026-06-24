.PHONY: build test run package dmg install clean

build:
	swift build

test:
	swift run ContainerCoreSmokeTests

run:
	swift run ContainerMenuBar

package:
	Scripts/package-app.sh

dmg:
	Scripts/make-dmg.sh

install: package
	rm -rf "/Applications/ContainerMenuBar.app"
	cp -R "$(CURDIR)/dist/ContainerMenuBar.app" "/Applications/ContainerMenuBar.app"
	@echo "Installed to /Applications/ContainerMenuBar.app — launch it from Finder or Spotlight."

clean:
	rm -rf .build dist ContainerMenuBar.app
