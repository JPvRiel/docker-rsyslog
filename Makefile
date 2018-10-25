# Include environment variables for testing/building via docker compose
include build.env
BUILD_DATE := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
export

define docker_tag_latest
	docker tag jpvriel/rsyslog:$(VERSION) jpvriel/rsyslog:latest
endef

build:
	$(info ## build $(VERSION) ($(BUILD_DATE)).)
	docker-compose -f docker-compose.yml build --build-arg RSYSLOG_VERSION --build-arg VERSION --build-arg BUILD_DATE --build-arg DISABLE_YUM_MIRROR=true --build-arg http_proxy --build-arg https_proxy --build-arg no_proxy
	$(call docker_tag_latest)

rebuild: clean
	$(info ## re-build $(VERSION) ($(BUILD_DATE)).)
	docker-compose -f docker-compose.yml build --no-cache --pull --build-arg RSYSLOG_VERSION --build-arg VERSION --build-arg BUILD_DATE --build-arg DISABLE_YUM_MIRROR=true --build-arg http_proxy --build-arg https_proxy --build-arg no_proxy
	$(call docker_tag_latest)

build_test:
	$(info ## build test $(VERSION) ($(BUILD_DATE)).)
	docker-compose -f docker-compose.test.yml build --build-arg RSYSLOG_VERSION --build-arg VERSION --build-arg BUILD_DATE --build-arg DISABLE_YUM_MIRROR=true --build-arg http_proxy --build-arg https_proxy --build-arg no_proxy
	$(call docker_tag_latest)

rebuild_test: clean_test
	$(info ## re-build test $(VERSION) ($(BUILD_DATE)).)
	docker-compose -f docker-compose.test.yml build --no-cache --pull --build-arg RSYSLOG_VERSION --build-arg VERSION --build-arg BUILD_DATE --build-arg DISABLE_YUM_MIRROR=true --build-arg http_proxy --build-arg https_proxy --build-arg no_proxy
	$(call docker_tag_latest)

clean: clean_test
	$(info ## remove $(VERSION).)
	docker rmi jpvriel/rsyslog:$(VERSION) jpvriel/rsyslog:latest
	docker system prune -f --filter 'label=org.label-schema.name=rsyslog'

clean_test:
	$(info ## clean test.)
	docker-compose -f docker-compose.test.yml down -v --rmi 'local'

# A failed test won't run the next command to clean, so clean before just in case
# Assume sudo might be used due to the security risk of adding a normal user to the docker group, so chown the config check files copied into the test dir
test: clean_test build
	$(info ## test.)
	docker-compose -f docker-compose.test.yml run sut
	rm -rf test/config_check/*
	docker cp $$(docker-compose -f docker-compose.test.yml ps -q test_syslog_server_config):/tmp/config_check test/
	if [ -n "$$SUDO_UID" -a -n "$$SUDO_GID" ]; then chown -R "$$SUDO_UID:$$SUDO_GID" test/config_check; fi
	docker-compose -f docker-compose.test.yml down -v --rmi 'local'

test_config: clean_test
	$(info ## test config.)
	docker-compose -f docker-compose.test.yml run test_syslog_server_config
	rm -rf test/config_check/*
	docker cp $$(docker-compose -f docker-compose.test.yml ps -q test_syslog_server_config):/tmp/config_check test/
	if [ -n "$$SUDO_UID" -a -n "$$SUDO_GID" ]; then chown -R "$$SUDO_UID:$$SUDO_GID" test/config_check; fi
	docker-compose -f docker-compose.test.yml down -v --rmi 'local'

#push: test
#	docker-compose -f docker-compose.yml push
