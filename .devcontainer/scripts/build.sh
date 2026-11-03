#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Weidmueller Interface GmbH & Co. KG
#
# Compile mstpd, mstpctl and unit tests with gcc using strict warnings.
# Usage: .devcontainer/scripts/build.sh [-t]
#   -t  also build and run unit tests (requires cmocka)
# The build directory is wiped on every run.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR/../.."

BUILD_DIR=build
CC=${CC:-gcc}
RUN_TESTS=0

while getopts "t" opt; do
	case $opt in
	t) RUN_TESTS=1 ;;
	*) sed -n '2,5p' "$0"; exit 1 ;;
	esac
done

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Appended after mstpd_CFLAGS from Makefile.am, so these take precedence.
CFLAGS=(
	-Wall
	-Wextra
	-Wformat=2
	-Wformat-security
	# These gave lots of warnings but are not critical for now
	# So I disabled them for now
	-Wno-unused-parameter
	-Wno-sign-compare
)

echo "==> Configuring"
autoreconf -i
cd "$BUILD_DIR"
../configure --quiet CC="$CC" CFLAGS="${CFLAGS[*]}"

# -s hides recipe echo, V=0 prints only "CC file.o"; warnings still go to stderr.
MAKE=(make -s V=0 -j"$(nproc)")

echo "==> Building mstpd, mstpctl"
"${MAKE[@]}"

if ((RUN_TESTS)); then
	echo "==> Building and running tests"
	"${MAKE[@]}" check VERBOSE=1
fi

echo "==> Done: $BUILD_DIR/mstpd, $BUILD_DIR/mstpctl"
