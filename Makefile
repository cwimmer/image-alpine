# -*- mode: makefile;-*-
.PHONY: update-versions commit-updates

alpine_short_version=$(shell cat ALPINE_SHORT_VERSION)
alpine_version=$(shell cat ALPINE_VERSION)
DATE = $(shell date +%Y-%m-%dT%H-%M-%S%z)
IMAGE_NAME=registry.digitalocean.com/cwimmer/alpine
IMAGE_NAME_INTERMEDIATE=$(IMAGE_NAME):intermediate

all: update-submodule build upload commit-updates

update-versions:
	$(MAKE) -f Makefile.update update-versions

commit-updates:
	git add *_VERSION docker-alpine .gitmodules
	git diff-index --quiet HEAD || git commit \
	-m "Local Version: $(shell cat ALPINE_LOCAL_VERSION)"
	-m "Alpine: $(alpine_version)" \
	-m "Updating versions Alpine: $(alpine_short_version)" \
	git push

update-submodule:
	cd docker-alpine; \
	git checkout master; \
	git pull; \
	git checkout v$(alpine_short_version)

build:
	echo $(alpine_short_version).$(DATE) > ALPINE_LOCAL_VERSION
	docker build -t $(IMAGE_NAME_INTERMEDIATE) docker-alpine/x86_64
	docker build -t $(IMAGE_NAME):`cat ALPINE_LOCAL_VERSION` dockerfile

upload:
	docker login registry.digitalocean.com \
	--username $(DO_REG_USERNAME) \
	--password $(DO_REG_PASSWORD)
	docker push $(IMAGE_NAME):$(shell cat ALPINE_LOCAL_VERSION)

