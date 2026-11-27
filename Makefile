.PHONY: app install test icon signing clean logs

app:        ## Build build/Smolix.app
	./scripts/build-app.sh

install:    ## Build, copy to /Applications and launch
	./scripts/install.sh

test:       ## Run unit tests
	swift test

icon:       ## Regenerate App/AppIcon.icns
	swift scripts/make-icon.swift App/AppIcon.icns

signing:    ## Create the local signing identity (done automatically on first build)
	./scripts/setup-signing.sh

logs:       ## Stream Smolix logs (tap restarts, debug wheel events)
	log stream --style compact --level debug --predicate 'subsystem == "dev.smolix.Smolix"'

clean:
	rm -rf .build build
