AC_PREREQ([2.61])
AC_INIT([mstpd], [0.0.4], [https://github.com/mstpd/mstpd])

# bridge-stp must be installed in /sbin/, and the associated scripts and
# executables should be installed outside of /usr/ by default.  If `./configure`
# was run without specifying `--exec-prefix=...`, then set the default
# exec_prefix so these files will be installed in the correct paths by default.
# AC_PREFIX_DEFAULT(...) can be used to override the default prefix, but there
# doesn't seem to be any standard macro to override the default exec_prefix, so
# just do it manually.
test "x$exec_prefix" = xNONE && exec_prefix=''

AM_INIT_AUTOMAKE([foreign -Wall])

AC_CONFIG_MACRO_DIR([m4])

AC_PROG_CC
m4_ifdef([AM_PROG_AR], [AM_PROG_AR])
LT_INIT

# Optional building of examples
AC_ARG_ENABLE([devel],
	[AC_HELP_STRING([--enable-devel], [build devel mode])],
	[enable_devel=yes], [])

AM_CONDITIONAL([ENABLE_DEVEL], [test "$enable_devel" = yes])

# Define PACKAGE_BUILD
PACKAGE_BUILD=`git log --pretty=format:'%h' -n 1`
AC_SUBST(PACKAGE_BUILD)
AC_DEFINE_UNQUOTED(PACKAGE_BUILD, "$PACKAGE_BUILD", [Build revision obtained from git])

# Override PACKAGE_VERSION to include git tag
PACKAGE_VERSION="${PACKAGE_VERSION}-${PACKAGE_BUILD}"
AC_SUBST(PACKAGE_VERSION)
AC_DEFINE_UNQUOTED(PACKAGE_VERSION, "$PACKAGE_VERSION", [Package version, including build number])

AC_SEARCH_LIBS([clock_gettime], [rt])

AC_CHECK_TYPES(struct timespec)
AC_CHECK_FUNCS(clock_gettime)

AC_CONFIG_HEADERS([config.h])
AC_CONFIG_FILES([Makefile])

AC_OUTPUT
