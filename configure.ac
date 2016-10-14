AC_PREREQ([2.61])
AC_INIT([mstpd], [0.0.4], [https://github.com/mstpd/mstpd])

AM_INIT_AUTOMAKE([foreign -Wall])

AC_CONFIG_MACRO_DIR([m4])

AC_PROG_CC
AM_PROG_AR
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
