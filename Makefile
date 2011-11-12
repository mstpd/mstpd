version := 0.01

DSOURCES = main.c epoll_loop.c brmon.c bridge_track.c libnetlink.c mstp.c \
           packet.c netif_utils.c ctl_socket_server.c hmac_md5.c driver_deps.c

DOBJECTS = $(DSOURCES:.c=.o)

CTLSOURCES = ctl_main.c ctl_socket_client.c

CTLOBJECTS = $(CTLSOURCES:.c=.o)

CFLAGS += -Werror -O2 -D_REENTRANT -D__LINUX__ -DVERSION=$(version) -I. \
          -D_GNU_SOURCE -D__LIBC_HAS_VERSIONSORT__

all: mstpd mstpctl

mstpd: $(DOBJECTS)
	$(CC) -o $@ $(DOBJECTS)

mstpctl: $(CTLOBJECTS)
	$(CC) -o $@ $(CTLOBJECTS)

-include .depend

clean:
	rm -f *.o *~ .depend.bak mstpd mstpctl

install: all
	-mkdir -pv $(DESTDIR)/sbin
	install -m 755 mstpd $(DESTDIR)/sbin/mstpd
	install -m 755 mstpctl $(DESTDIR)/sbin/mstpctl
	install -m 755 bridge-stp $(DESTDIR)/sbin/bridge-stp

romfs: all
	$(ROMFSINST) /sbin/mstpd
	$(ROMFSINST) /sbin/mstpctl
	$(ROMFSINST) /sbin/bridge-stp

#depend:
#	makedepend -I. -Y *.c -f .depend
