MODE = devel
version := 0.04

DSOURCES = main.c epoll_loop.c brmon.c bridge_track.c libnetlink.c mstp.c \
           packet.c netif_utils.c ctl_socket_server.c hmac_md5.c driver_deps.c

DOBJECTS = $(DSOURCES:.c=.o)

CTLSOURCES = ctl_main.c ctl_socket_client.c

CTLOBJECTS = $(CTLSOURCES:.c=.o)

CFLAGS += -Os -Wall -Werror -D_REENTRANT -D__LINUX__ -DVERSION=$(version) -I. \
          -D_GNU_SOURCE -D__LIBC_HAS_VERSIONSORT__

ifeq ($(MODE),devel)
CFLAGS += -g3 -O0
endif

all: mstpd mstpctl

mstpd: $(DOBJECTS)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $(DOBJECTS) $(LDFLAGS)

mstpctl: $(CTLOBJECTS)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $(CTLOBJECTS) $(LDFLAGS)

-include .depend

clean:
	rm -f *.o *~ .depend.bak mstpd mstpctl

install: all
	-mkdir -pv $(DESTDIR)/sbin
	install -m 755 mstpd $(DESTDIR)/sbin/mstpd
	install -m 755 mstpctl $(DESTDIR)/sbin/mstpctl
	install -m 755 bridge-stp $(DESTDIR)/sbin/bridge-stp
	-mkdir -pv $(DESTDIR)/lib/mstpctl-utils/
	cp -rv lib/* $(DESTDIR)/lib/mstpctl-utils/
	gzip -f $(DESTDIR)/lib/mstpctl-utils/mstpctl.8
	gzip -f $(DESTDIR)/lib/mstpctl-utils/mstpctl-utils-interfaces.5
	if [ -d $(DESTDIR)/etc/network/if-pre-up.d ] ; then ln -sf /lib/mstpctl-utils/ifupdown.sh $(DESTDIR)/etc/network/if-pre-up.d/mstpctl ; fi
	if [ -d $(DESTDIR)/etc/network/if-pre-up.d ] ; then ln -sf /lib/mstpctl-utils/ifupdown.sh $(DESTDIR)/etc/network/if-post-down.d/mstpctl ; fi
	if [ -d $(DESTDIR)/etc/bash_completion.d ] ; then ln -sf /lib/mstpctl-utils/bash_completion $(DESTDIR)/etc/bash_completion.d/mstpctl ; fi
	-mkdir -pv $(DESTDIR)/usr/share/man/man8/
	ln -sf /lib/mstpctl-utils/mstpctl.8.gz $(DESTDIR)/usr/share/man/man8/mstpctl.8.gz
	-mkdir -pv $(DESTDIR)/usr/share/man/man5/
	ln -sf /lib/mstpctl-utils/mstpctl-utils-interfaces.5.gz $(DESTDIR)/usr/share/man/man5/mstpctl-utils-interfaces.5.gz

romfs: all
	$(ROMFSINST) /sbin/mstpd
	$(ROMFSINST) /sbin/mstpctl
	$(ROMFSINST) /sbin/bridge-stp

#depend:
#	makedepend -I. -Y *.c -f .depend
