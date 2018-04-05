# Include environment variables for testing/building via docker compose
include build.env
BUILD_DATE := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
export

# Don't use docker-compose due cache coherence issues - docker build seems more reliable
# See: https://github.com/docker/docker-py/issues/998
build:
	docker pull centos
	docker build --build-arg RSYSLOG_VERSION --build-arg VERSION --build-arg BUILD_DATE --build-arg DISABLE_YUM_MIRROR=true --build-arg http_proxy --build-arg https_proxy --build-arg no_proxy -t jpvriel/rsyslog:$(VERSION) -t jpvriel/rsyslog:latest .
	$(info ## build $(VERSION) ($(BUILD_DATE)).)

clean: clean_test
	docker rmi jpvriel/rsyslog:$(VERSION) jpvriel/rsyslog:latest
	docker system prune -f --filter 'label=org.label-schema.name=rsyslog' --filter 'dangling=true'
	$(info ## remove $(VERSION))

rebuild: clean build

clean_test:
	docker-compose -f docker-compose.test.yml down -v --rmi 'local'

# A failed test won't run the next command to clean, so clean before in case
test: clean_test build
	docker-compose -f docker-compose.test.yml run --rm sut
	docker-compose -f docker-compose.test.yml down -v --rmi 'local'

#push: test
#	docker-compose -f docker-compose.yml push
