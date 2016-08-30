ACLOCAL_AMFLAGS = -I m4

sbin_PROGRAMS = mstpd mstpctl

mstpd_SOURCES = \
	main.c epoll_loop.c brmon.c bridge_track.c libnetlink.c mstp.c \
	packet.c netif_utils.c ctl_socket_server.c hmac_md5.c driver_deps.c
mstpctl_SOURCES = \
	ctl_main.c ctl_socket_client.c

BUILDDEF = $(shell git log --pretty=format:'%h' -n 1)

mstpd_CFLAGS = \
	-Os -Wall -Werror -D_REENTRANT -D__LINUX__ -DVERSION=$(VERSION) -DBUILD="$(BUILDDEF)" -I. \
	-D_GNU_SOURCE -D__LIBC_HAS_VERSIONSORT__
if ENABLE_DEVEL
  mstpd_CFLAGS += -g3 -O0
endif
mstpctl_CFLAGS = $(mstpd_CFLAGS)

mstpdir=$(DESTDIR)$(libdir)/mstpctl-utils
etcdir=$(DESTDIR)$(sysconfdir)
man5dir=$(DESTDIR)$(mandir)/man5
man8dir=$(DESTDIR)$(mandir)/man8

install-data-hook:
	install -m 755 bridge-stp $(DESTDIR)$(sbindir)/bridge-stp
	mkdir -pv $(mstpdir)
	cp -rv lib/* $(mstpdir)
	gzip -f $(mstpdir)/mstpctl.8
	gzip -f $(mstpdir)/mstpctl-utils-interfaces.5
	if [ -d $(etcdir)/network/if-pre-up.d ] ; then ln -sf $(mstpdir)/ifupdown.sh $(etcdir)/network/if-pre-up.d/mstpctl ; fi
	if [ -d $(etcdir)/network/if-post-down.d ] ; then ln -sf $(mstpdir)/ifupdown.sh $(etcdir)/network/if-post-down.d/mstpctl ; fi
	if [ -d $(etcdir)/bash_completion.d ] ; then ln -sf $(mstpdir)/bash_completion $(etcdir)/bash_completion.d/mstpctl ; fi
	mkdir -pv $(man8dir)
	ln -sf $(mstpdir)/mstpctl.8.gz $(man8dir)/mstpctl.8.gz
	mkdir -pv $(man5dir)
	ln -sf $(mstpdir)/mstpctl-utils-interfaces.5.gz $(man5dir)/mstpctl-utils-interfaces.5.gz
