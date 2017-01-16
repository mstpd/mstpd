ACLOCAL_AMFLAGS = -I m4

sbin_PROGRAMS = mstpd mstpctl

mstpd_SOURCES = \
	main.c epoll_loop.c brmon.c bridge_track.c libnetlink.c mstp.c \
	packet.c netif_utils.c ctl_socket_server.c hmac_md5.c driver_deps.c
mstpctl_SOURCES = \
	ctl_main.c ctl_socket_client.c

mstpd_CFLAGS = \
	-Os -Wall -Werror -D_REENTRANT -D__LINUX__ -I. \
	-D_GNU_SOURCE
if ENABLE_DEVEL
  mstpd_CFLAGS += -g3 -O0
endif
mstpctl_CFLAGS = $(mstpd_CFLAGS)

all-local: bridge-stp lib/ifupdown.sh

utilsdir=$(libexecdir)/mstpctl-utils

mstpctlfile=$(sbindir)/mstpctl
mstpdpidfile=$(localstatedir)/run/mstpd.pid
bridgestpconffile=$(sysconfdir)/bridge-stp.conf
utilsfuncfile=$(utilsdir)/mstpctl-utils.sh

mstpd_CFLAGS += -DMSTPD_PID_FILE='"$(mstpdpidfile)"'

# See https://www.gnu.org/savannah-checkouts/gnu/autoconf/manual/autoconf-2.69/html_node/Installation-Directory-Variables.html#index-sysconfdir-188
populate_template = sed \
	-e 's|@sbindir[@]|$(sbindir)|g' \
	-e 's|@mstpctlfile[@]|$(mstpctlfile)|g' \
	-e 's|@mstpdpidfile[@]|$(mstpdpidfile)|g' \
	-e 's|@bridgestpconffile[@]|$(bridgestpconffile)|g' \
	-e 's|@utilsfuncfile[@]|$(utilsfuncfile)|g'
bridge-stp lib/ifupdown.sh: Makefile
	rm -f $@ $@.tmp
	srcdir=''; test -f ./$@.in || srcdir="$(srcdir)/"; \
	$(populate_template) $${srcdir}$@.in > $@.tmp
	chmod 755 $@.tmp
	mv $@.tmp $@
bridge-stp: $(srcdir)/bridge-stp.in
lib/ifupdown.sh: $(srcdir)/lib/ifupdown.sh.in

mstpdir=$(DESTDIR)$(utilsdir)
etcdir=$(DESTDIR)$(sysconfdir)
man5dir=$(DESTDIR)$(mandir)/man5
man8dir=$(DESTDIR)$(mandir)/man8
docdest=$(DESTDIR)$(docdir)

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
	mkdir -pv $(docdest)
	install -m 644 README.VLANs.md $(docdest)/README.VLANs
