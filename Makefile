APP = build/HandsFreeNotch.app

.PHONY: app run test install clean

app:            ## Build the .app (release)
	scripts/bundle.sh

run: app        ## Build and launch
	open $(APP)

test:           ## Run the router tests
	swift test

install: app    ## Copy to /Applications and launch from there
	rm -rf /Applications/HandsFreeNotch.app
	cp -R $(APP) /Applications/HandsFreeNotch.app
	open /Applications/HandsFreeNotch.app

clean:
	rm -rf .build build
