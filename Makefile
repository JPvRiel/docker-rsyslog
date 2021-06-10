# Include environment variables for testing/building via docker compose
include build.env
BUILD_DATE := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
export

define docker_tag_latest
	docker tag jpvriel/rsyslog:$(VERSION) jpvriel/rsyslog:latest
endef

# Check if a proxy is defined use and optomise build to use it
DOCKER_COMPOSE_PROXY_BUILD_ARGS =
ifdef http_proxy
DOCKER_COMPOSE_PROXY_BUILD_ARGS = --build-arg DISABLE_YUM_MIRROR=true --build-arg http_proxy --build-arg https_proxy --build-arg no_proxy
endif
ifdef https_proxy
DOCKER_COMPOSE_PROXY_BUILD_ARGS = --build-arg DISABLE_YUM_MIRROR=true --build-arg http_proxy --build-arg https_proxy --build-arg no_proxy
endif
ifeq ($(DOCKER_COMPOSE_PROXY_BUILD_ARGS),)
$(info ## No proxy env vars found.)
else
$(info ## Proxy env vars found and will be passed onto docker-compose as build args.)
endif

build:
	$(info ## build $(VERSION) ($(BUILD_DATE)).)
	docker-compose -f docker-compose.yml build --build-arg RSYSLOG_VERSION --build-arg VERSION --build-arg BUILD_DATE $(DOCKER_COMPOSE_PROXY_BUILD_ARGS)
	$(call docker_tag_latest)

rebuild:
	$(info ## re-build $(VERSION) ($(BUILD_DATE)).)
	docker-compose -f docker-compose.yml build --no-cache --pull --build-arg RSYSLOG_VERSION --build-arg VERSION --build-arg BUILD_DATE $(DOCKER_COMPOSE_PROXY_BUILD_ARGS)
	$(call docker_tag_latest)

build_test:
	$(info ## build test $(VERSION) ($(BUILD_DATE)).)
	docker-compose -f docker-compose.test.yml build --build-arg RSYSLOG_VERSION --build-arg VERSION --build-arg BUILD_DATE $(DOCKER_COMPOSE_PROXY_BUILD_ARGS)
	$(call docker_tag_latest)

rebuild_test: clean_test
	$(info ## re-build test $(VERSION) ($(BUILD_DATE)).)
	docker-compose -f docker-compose.test.yml build --no-cache --pull --build-arg RSYSLOG_VERSION --build-arg VERSION --build-arg BUILD_DATE $(DOCKER_COMPOSE_PROXY_BUILD_ARGS)
	$(call docker_tag_latest)

clean: clean_test
	$(info ## remove $(VERSION).)
	docker rmi jpvriel/rsyslog:$(VERSION) jpvriel/rsyslog:latest
	#docker image prune -f --filter 'label=org.label-schema.name=rsyslog'
	#docker system prune -f --filter 'label=org.label-schema.name=rsyslog'

clean_test:
	$(info ## clean test.)
	docker-compose -f docker-compose.test.yml down -v --rmi 'local'
	docker container prune -f --filter 'label=com.docker.compose.project=docker-rsyslog'
	docker volume prune -f --filter 'label=com.docker.compose.project=docker-rsyslog'
	rm -rf test/config_check/*

# A failed test won't run the next command to clean, so clean before just in case
# Assume sudo might be used due to the security risk of adding a normal user to the docker group, so chown the config check files copied into the test dir

test_config: build
	$(info ## test config.)
	rm -rf test/config_check/*
	docker-compose -f docker-compose.test.yml run test_syslog_server_config
	if [ -n "$$SUDO_UID" -a -n "$$SUDO_GID" ]; then chown -R "$$SUDO_UID:$$SUDO_GID" test/config_check; fi
	docker-compose -f docker-compose.test.yml down -v --rmi 'local'

test: clean_test build
	$(info ## test.)
	docker-compose -f docker-compose.test.yml run sut
	if [ -n "$$SUDO_UID" -a -n "$$SUDO_GID" ]; then chown -R "$$SUDO_UID:$$SUDO_GID" test/config_check; fi
	docker-compose -f docker-compose.test.yml down -v --rmi 'local'

test_debug_fail: clean_test build
	$(info ## test and stop on first failure along with triggering the python debugger.)
	docker-compose -f docker-compose.test.yml run sut behave --define BEHAVE_DEBUG_ON_ERROR --stop --no-capture --no-capture-stderr --no-logcapture --format plain --logging-level debug behave/features
	if [ -n "$$SUDO_UID" -a -n "$$SUDO_GID" ]; then chown -R "$$SUDO_UID:$$SUDO_GID" test/config_check; fi
	docker-compose -f docker-compose.test.yml down -v --rmi 'local'

test_wip: clean_test build
	$(info ## test and stop on first failure along with triggering the python debugger.)
	docker-compose -f docker-compose.test.yml run sut behave  --define BEHAVE_DEBUG_ON_ERROR --wip --logging-level debug --stop behave/features
	if [ -n "$$SUDO_UID" -a -n "$$SUDO_GID" ]; then chown -R "$$SUDO_UID:$$SUDO_GID" test/config_check; fi
	docker-compose -f docker-compose.test.yml down -v --rmi 'local'

test_no_teardown: clean_test build
	$(info ## test.)
	docker-compose -f docker-compose.test.yml run sut
	if [ -n "$$SUDO_UID" -a -n "$$SUDO_GID" ]; then chown -R "$$SUDO_UID:$$SUDO_GID" test/config_check; fi

#push: test
#	docker-compose -f docker-compose.yml push
