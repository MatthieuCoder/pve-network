SUBDIRS := PVE services

all:
	set -e && for i in $(SUBDIRS); do $(MAKE) -C $$i; done

.PHONY: clean
clean:
	$(MAKE) -C test $@
	set -e && for i in $(SUBDIRS); do $(MAKE) -C $$i $@; done

.PHONY: test
test:
	echo "skipping tests"
	# $(MAKE) -C $@

.PHONY: install
install:
	set -e && for i in $(SUBDIRS); do $(MAKE) -C $$i $@; done
