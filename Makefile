.PHONY: build publish

QBT_VERSION := 5.0.1
LIBBT_VERSION := 2.0.10

VERSION := 1.0.14
TAG :=  magnus2468/qbittorrent-vpn

all: build publish

publish:
	docker build \
	--build-arg QBT_VERSION=$(QBT_VERSION) \
	--build-arg LIBBT_VERSION=$(LIBBT_VERSION) \
	--tag "$(TAG):$(VERSION)" .  
	docker tag "$(TAG):$(VERSION)" "$(TAG):$(VERSION)" 
	docker push "$(TAG):$(VERSION)" 

build:
	docker build \
	--build-arg QBT_VERSION=$(QBT_VERSION) \
	--build-arg LIBBT_VERSION=$(LIBBT_VERSION) \
	--tag "$(TAG):$(VERSION)" .  
 