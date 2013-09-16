VERSION=1.0
TARGET=deb
NAME=sensu-community-plugins
PREFIX=/etc/sensu/plugins
MAINTAINER="$(USER)@$(shell hostname)"
VENDOR="Community"
URL=$(shell git config remote.origin.url)
LICENSE=MIT
DESCRIPTION="Collection of plugins for Sensu maintained by the community"

SOURCES=extensions handlers mutators plugins

.PHONY=package

package:
	fakeroot fpm -f -n $(NAME) -v $(VERSION) --license=$(LICENSE) --vendor=$(VENDOR) --url $(URL) -m $(MAINTAINER) --category=Monitoring -s dir -t $(TARGET) --description=$(DESCRIPTION) --prefix $(PREFIX) $(SOURCES)
