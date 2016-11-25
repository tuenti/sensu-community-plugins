VERSION=2.3.17
TARGET=deb
LOGLEVEL="warn"
NAME=sensu-community-plugins
PREFIX=/etc/sensu
MAINTAINER="$(shell git config user.email)"
VENDOR="Community"
URL=$(shell git config remote.origin.url)
LICENSE="MIT"
CATEGORY="Monitoring"
DESCRIPTION="Collection of plugins for Sensu maintained by the community"
SOURCES=extensions handlers mutators plugins


.PHONY=package


all: clean package

clean:
	@rm -f $(NAME)_$(VERSION)*.$(TARGET)

package: $(SOURCES)
	@fpm -t $(TARGET) -s dir --prefix $(PREFIX) --log $(LOGLEVEL) --force --name $(NAME) --version $(VERSION) --license $(LICENSE) --vendor $(VENDOR) --url $(URL) --maintainer $(MAINTAINER) --description $(DESCRIPTION) --category $(CATEGORY) -a all $?
