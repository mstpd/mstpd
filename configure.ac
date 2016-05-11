AC_PREREQ([2.61])
AC_INIT([mstpd], [0.0.4], [https://github.com/ocedo/mstpd])

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

AC_CONFIG_HEADERS([config.h])
AC_CONFIG_FILES([Makefile])

AC_OUTPUT
