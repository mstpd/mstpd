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

all-local: bridge-stp lib/ifupdown.sh lib/mstp_config_bridge

utilsdir=$(libexecdir)/mstpctl-utils

mstpctlfile=$(sbindir)/mstpctl
mstpdpidfile=$(localstatedir)/run/mstpd.pid
bridgestpconffile=$(sysconfdir)/bridge-stp.conf
ifupdownfile=$(utilsdir)/ifupdown.sh
utilsfuncfile=$(utilsdir)/mstpctl-utils-functions.sh
ifqueryfile=$(utilsdir)/ifquery

mstpd_CFLAGS += -DMSTPD_PID_FILE='"$(mstpdpidfile)"'

# See https://www.gnu.org/savannah-checkouts/gnu/autoconf/manual/autoconf-2.69/html_node/Installation-Directory-Variables.html#index-sysconfdir-188
populate_template = sed \
	-e 's|@sbindir[@]|$(sbindir)|g' \
	-e 's|@mstpctlfile[@]|$(mstpctlfile)|g' \
	-e 's|@mstpdpidfile[@]|$(mstpdpidfile)|g' \
	-e 's|@bridgestpconffile[@]|$(bridgestpconffile)|g' \
	-e 's|@ifupdownfile[@]|$(ifupdownfile)|g' \
	-e 's|@utilsfuncfile[@]|$(utilsfuncfile)|g' \
	-e 's|@ifqueryfile[@]|$(ifqueryfile)|g'
bridge-stp lib/ifupdown.sh lib/mstp_config_bridge: Makefile
	rm -f $@ $@.tmp
	srcdir=''; test -f ./$@.in || srcdir="$(srcdir)/"; \
	$(populate_template) $${srcdir}$@.in > $@.tmp
	chmod 755 $@.tmp
	mv $@.tmp $@
bridge-stp: $(srcdir)/bridge-stp.in
lib/ifupdown.sh: $(srcdir)/lib/ifupdown.sh.in
lib/mstp_config_bridge: $(srcdir)/lib/mstp_config_bridge.in

sbindest=$(DESTDIR)$(sbindir)
utilsdest=$(DESTDIR)$(utilsdir)
etcdest=$(DESTDIR)$(sysconfdir)
bashcompdest=$(etcdest)/bash_completion.d
man5dest=$(DESTDIR)$(mandir)/man5
man8dest=$(DESTDIR)$(mandir)/man8
docdest=$(DESTDIR)$(docdir)

install-data-hook:
	install -m 755 bridge-stp $(sbindest)/bridge-stp
	mkdir -pv $(etcdest)
	install -m 644 bridge-stp.conf $(etcdest)/bridge-stp.conf
	mkdir -pv $(utilsdest)
	install -m 755 lib/ifupdown.sh $(utilsdest)
	install -m 644 lib/mstpctl-utils-functions.sh $(utilsdest)
	install -m 755 lib/mstpctl_restart_config $(utilsdest)
	install -m 755 lib/mstp_config_bridge $(utilsdest)
	install -m 755 lib/ifquery $(utilsdest)
	if [ -d $(etcdest)/network/if-pre-up.d ] ; then ln -sf $(utilsdir)/ifupdown.sh $(etcdest)/network/if-pre-up.d/mstpctl ; fi
	if [ -d $(etcdest)/network/if-post-down.d ] ; then ln -sf $(utilsdir)/ifupdown.sh $(etcdest)/network/if-post-down.d/mstpctl ; fi
	mkdir -pv $(bashcompdest)
	install -m 644 lib/bash_completion $(bashcompdest)/mstpctl
	mkdir -pv $(man8dest)
	install -m 644 lib/mstpctl.8 $(man8dest)/mstpctl.8
	gzip -f $(man8dest)/mstpctl.8
	mkdir -pv $(man5dest)
	install -m 644 lib/mstpctl-utils-interfaces.5 $(man5dest)/mstpctl-utils-interfaces.5
	gzip -f $(man5dest)/mstpctl-utils-interfaces.5
	mkdir -pv $(docdest)
	install -m 644 README.VLANs.md $(docdest)/README.VLANs
