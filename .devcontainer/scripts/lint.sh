#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Weidmueller Interface GmbH & Co. KG
#
# Run clang-tidy over the mstpd and mstpctl sources, using the exact compile
# commands of the autotools build, focusing on undefined behavior and pointer misuse.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR/../.."

RUN_CLANG_TIDY=${RUN_CLANG_TIDY:-run-clang-tidy}

for tool in "$RUN_CLANG_TIDY" bear; do
	if ! command -v "$tool" >/dev/null; then
		echo "error: $tool not found (apt install clang-tidy bear)" >&2
		exit 2
	fi
done

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Undefined behavior, pointer/memory misuse, and common C mistakes.
CHECKS=(
	-*
	clang-analyzer-*
	bugprone-*
	concurrency-*
	# These give a ton of warnings and are not critical for now
	-concurrency-mt-unsafe
	-clang-analyzer-security.insecureAPI.*
	-bugprone-multi-level-implicit-pointer-conversion
	-bugprone-narrowing-conversions
	-bugprone-assignment-in-if-condition
	-bugprone-macro-parentheses
	-bugprone-reserved-identifier
	-bugprone-switch-missing-default-case
	-bugprone-easily-swappable-parameters
)
CHECKS_CSV=$(IFS=,; echo "${CHECKS[*]}")

echo "==> Recording compile commands"
autoreconf -i
SRC_DIR=$PWD
(cd "$TMP_DIR" && "$SRC_DIR/configure" --quiet && bear -- make -j"$(nproc)" >/dev/null)

echo "==> clang-tidy"
# Header filter limits diagnostics to this repo's own headers.
"$RUN_CLANG_TIDY" -quiet \
	-use-color \
	-p "$TMP_DIR" \
	-checks="$CHECKS_CSV" \
	-header-filter="^$PWD/.*"

echo "==> Done"
