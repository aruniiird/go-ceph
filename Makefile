DOCKER_CI_IMAGE = go-ceph-ci
CONTAINER_CMD := docker
CONTAINER_OPTS := --security-opt $(shell grep -q selinux /sys/kernel/security/lsm && echo "label=disable" || echo "apparmor:unconfined")
CONTAINER_CONFIG_DIR := testing/containers/ceph
VOLUME_FLAGS := 
CEPH_VERSION := nautilus
RESULTS_DIR :=
CHECK_GOFMT_FLAGS := -e -s -l
IMPLEMENTS_OPTS :=

SELINUX := $(shell getenforce 2>/dev/null)
ifeq ($(SELINUX),Enforcing)
	VOLUME_FLAGS = :z
endif

ifdef RESULTS_DIR
	RESULTS_VOLUME := -v $(RESULTS_DIR):/results$(VOLUME_FLAGS)
endif

build:
	go build -v -tags $(CEPH_VERSION) $(shell go list ./... | grep -v /contrib)
fmt:
	go fmt ./...
test:
	go test -v ./...

.PHONY: test-docker test-container
test-docker: test-container
test-container: check-ceph-version .build-docker $(RESULTS_DIR)
	$(CONTAINER_CMD) run --device /dev/fuse --cap-add SYS_ADMIN $(CONTAINER_OPTS) --rm -v $(CURDIR):/go/src/github.com/ceph/go-ceph$(VOLUME_FLAGS) $(RESULTS_VOLUME) $(DOCKER_CI_IMAGE)

ifdef RESULTS_DIR
$(RESULTS_DIR):
	mkdir -p $(RESULTS_DIR)
endif

.PHONY: ci-image
ci-image: .build-docker
.build-docker: $(CONTAINER_CONFIG_DIR)/Dockerfile entrypoint.sh
	$(CONTAINER_CMD) build --build-arg CEPH_VERSION=$(CEPH_VERSION) -t $(DOCKER_CI_IMAGE) -f $(CONTAINER_CONFIG_DIR)/Dockerfile .
	@$(CONTAINER_CMD) inspect -f '{{.Id}}' $(DOCKER_CI_IMAGE) > .build-docker
	echo $(CEPH_VERSION) >> .build-docker

# check-ceph-version checks for the last used Ceph version in the container
# image and forces a rebuild of the image in case the Ceph version changed
.PHONY: check-ceph-version
check-ceph-version:
	@grep -wq '$(CEPH_VERSION)' .build-docker 2>/dev/null || $(RM) .build-docker

check: check-revive check-format

check-format:
	! gofmt $(CHECK_GOFMT_FLAGS) . | sed 's,^,formatting error: ,' | grep 'go$$'

check-revive:
	# Configure project's revive checks using .revive.toml
	# See: https://github.com/mgechev/revive
	revive -config .revive.toml $$(go list ./... | grep -v /vendor/)

# Do a quick compile only check of the tests and impliclity the
# library code as well.
test-binaries: \
	cephfs.test \
	internal/callbacks.test \
	internal/cutil.test \
	internal/errutil.test \
	internal/retry.test \
	rados.test \
	rbd.test
test-bins: test-binaries

%.test: % force_go_build
	go test -c ./$<

implements:
	go build -o implements ./contrib/implements

check-implements: implements
	./implements $(IMPLEMENTS_OPTS) ./cephfs ./rados ./rbd

# force_go_build is phony and builds nothing, can be used for forcing
# go toolchain commands to always run
.PHONY: build fmt test test-docker check test-binaries test-bins force_go_build check-implements
