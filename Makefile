# Copyright 2022 Nathan (Blaise) Bruer
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

CARGO_VERSION := $(shell cargo --version)
ifndef CARGO_VERSION
$(error "No 'cargo' in $$PATH, please install cargo. eg: curl https://sh.rustup.rs -sSf | sh")
endif

s3pcp:
	# Make pjoin.
	@temp_dir=`mktemp --tmpdir -d` && \
	trap 'rm -rf $$temp_dir' EXIT && \
	cd $$temp_dir && \
	git clone https://github.com/allada/putils.git && \
	cd $$temp_dir/putils/pjoin && \
	cargo build --release && \
	mv $$temp_dir/putils/pjoin/target/release/pjoin /usr/bin/pjoin

	cp $(CURDIR)/s3pcp.sh /usr/bin/s3pcp
