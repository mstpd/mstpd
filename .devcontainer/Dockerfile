# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Weidmueller Interface GmbH & Co. KG
FROM mcr.microsoft.com/devcontainers/base:ubuntu

RUN apt-get update \
	&& export DEBIAN_FRONTEND=noninteractive \
	&& apt-get install -y --no-install-recommends \
		autoconf \
		automake \
		libtool \
		pkg-config \
		make \
		gcc \
		gdb \
		valgrind \
		clang-format \
		clang-tidy \
		bear \
		shellcheck \
		libcjson-dev \
		libmnl-dev \
		libcmocka-dev \
		linux-libc-dev \
		systemd \
		iproute2 \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*
