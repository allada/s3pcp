#!/bin/bash
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

set -euo pipefail

function print_help() {
  cat <<'EOT'
Downloads data from s3 and sends it to stdout very fast and on a pinned version.
Many concurrent connections to s3 are opened and different chunks of the file
are downloaded in parallel and stiched together using the `pjoin` utility.

USAGE:
    s3pcp [OPTIONS] [S3_PATH]

ARGS:
    S3_PATH    A path to an s3 object. Format: 's3://{bucket}/{key}'

OPTIONS:
    --requester-pays
        If the account downloading is requesting to be the payer for
        the request.

    --region <REGION>
        The region the request should be sent to.

    -p, --parallel-count <PARALLEL_COUNT>
        Number of commands to run in parallel [default: based on computer resources]

    -h, --help
        Print help information
EOT
}

if [[ $# -eq 0 ]]; then
  print_help
  echo "Not enough arguments"
  exit 1
fi

normalized_args=()
# Normalize our arguments.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --*=* )
      normalized_args+=("${1%=*}")
      normalized_args+=("${1#*=}")
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      normalized_args+=("$1")
      shift
      ;;
  esac
done

set -- "${normalized_args[@]}"

maybe_requester_pays=""
maybe_region=""
maybe_parallel_count=""
s3_path=""
while : ; do
  case "$1" in
    --requester-pays )
      maybe_requester_pays="--request-payer=requester"
      shift
      ;;
    --region)
      maybe_region="--region=$2"
      shift 2
      ;;
    -p | --parallel-count )
      maybe_parallel_count="--parallel-count=$2"
      shift 2
      ;;
    -h | --help)
      print_help
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      if [ -z "$s3_path" ] ; then
        s3_path="$1"
        shift
        break
      fi
      >&2 echo "Unexpected option: $1"
      exit 1
      ;;
  esac
done

bucket=""
key=""
if [[ $s3_path =~ s3://([^/]+)/(.*) ]] ; then
  bucket="${BASH_REMATCH[1]}"
  key="${BASH_REMATCH[2]}"
else
  >&2 echo "'$s3_path' is not a valid s3:// path"
  exit 1
fi

object_attributes_json=$(aws s3api get-object-attributes \
   $maybe_requester_pays \
   $maybe_region \
   --bucket $bucket \
   --key $key \
   --object-attributes ObjectParts)

# First get the latest version of the object, since this is live data it may change at any time.
# By using the version tag for everything we significantly reduce the chance of the download failing
# due to downloading when a new version is uploaded.
version=$(echo $object_attributes_json | jq -r ".VersionId")
# Get the number of parts of this object. We can then download them in parallel if we know how many.
parts_count=$(echo $object_attributes_json | jq -r ".ObjectParts.TotalPartsCount")

est_part_size=$(aws s3api head-object \
    $maybe_requester_pays \
    $maybe_region \
    --bucket $bucket \
    --key $key \
    --version-id $version\
    --part-number 1 \
  | jq -r ".ContentLength")

# Use the size of each chunk + 10% just in case there's some fence posts.
per_job_buffer=$(( est_part_size + est_part_size / 10 ))

avail_mem_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
parallel_downloads=$(( avail_mem_kb * 1000 / est_part_size ))
num_cores=$(nproc)
# This is an inverse log10(). The lower the number of cores you have the more processes you'll
# spawn. The logic here is that on less powerful machines you'll almost certainly want more
# than 1 download going on at a time. The same in reverse, on 128 core machines, you will be
# limited by network instead of cpu ability. 128 cores = 89 jobs, 64 cores = 56 jobs,
# 32 cores = 36 jobs, 16 cores = 25 jobs, 4 cores = 15 jobs, exc...
max_parallel_downloads=$(echo "x = $num_cores / (l(($num_cores + 8) / 8) / l(10)); scale=0; x / 1" | bc -l)
if [ $parallel_downloads -gt $max_parallel_downloads ]; then
  parallel_downloads=$max_parallel_downloads
fi

if [[ "$maybe_parallel_count" == "" ]] ; then
  maybe_parallel_count="--parallel-count=$parallel_downloads"
fi

# 1. First this will print out 1 to $parts_count
# 2. Replace each number with a shell command that will download just that part number of the file
#    to stdout.
# 3. Send each full command to `pjoin`, which will run each of those commands in order with a
#    buffer (specified by `-b`) and limit it to `-p` concurrent processes and pipe to stdout.
# This is an extremely fast way to download a large amount of data by downloading many sections
# in parallel, decompressing each chunk individually and combining them back together in a single
# stream/file. This process has shown to get at least 25Gb/s on high performance hardware, where
# using just standard ways (aws-cli + zstd on single stream) yields about 125mb/s.
# Note: Sadly s3api does not support a --quiet'like mode, so we write to stderr instead
# and then set stderr to stdout's file handle then set original stdout to null.
shell_command=$( echo "sh -c '
      aws s3api get-object
        $maybe_requester_pays
        --version-id $version
        --part-number %s
        --bucket $bucket
        --key $key
        /dev/stderr 2>&1 >/dev/null'" | tr '\n' ' ') # `tr` removes \n characters in string.
seq 1 $parts_count \
  | xargs printf "$shell_command\n" \
  | pjoin -b "$per_job_buffer" "$maybe_parallel_count"
