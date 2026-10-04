#!/usr/bin/env bash
#
# Copyright 2026 Sweden Connect
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Fetches the SAML metadata of each service of the local federation, and updates the entity metadata files that the
# metadata aggregator builds its feed from (config/metadata-aggregator/metadata).
#
# Run it after a change of a service's configuration or keys, with the services running. The aggregator reads the
# files again within a minute.
#
# Usage: scripts/refresh-metadata.sh [service] ...
#
# where service is one of reference, test-my-eid and test-client. Without arguments, the metadata of every service
# is fetched.
#
# The signature, validUntil and cacheDuration of the fetched metadata are removed, so that the committed files do not
# expire. The aggregator signs the feed and sets its validity.
#
# Requires curl and perl.
#

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
METADATA_DIR="${ROOT}/config/metadata-aggregator/metadata"
CA_FILE="${ROOT}/config/common/tls.crt"
HOST="local.fed.swedenconnect.se"

#
# Fetches the metadata of one entity and writes it to a file.
#
# $1 - the port of the service
# $2 - the path of the metadata
# $3 - the name of the file under config/metadata-aggregator/metadata
#
fetch() {
  local port="$1" path="$2" file="$3"
  local url="https://${HOST}:${port}${path}"
  local tmp
  tmp="$(mktemp)"

  echo "Fetching ${url} ..."
  # The host name is resolved to 127.0.0.1 here, so that the script also works without the hosts file entry.
  if ! curl -fsS --cacert "${CA_FILE}" --resolve "${HOST}:${port}:127.0.0.1" \
      -H "Accept: application/samlmetadata+xml, application/xml" -o "${tmp}" "${url}"; then
    rm -f "${tmp}"
    echo "Failed to fetch ${url}. Is the service running?" >&2
    return 1
  fi

  # Removes the signature of the entity descriptor, and its validUntil and cacheDuration attributes.
  perl -0777 -pe '
    s{<(\w+:)?Signature\b[^>]*>.*?</(\w+:)?Signature>\s*}{}s;
    s{(<(\w+:)?EntityDescriptor\b[^>]*?)\s+validUntil="[^"]*"}{$1}s;
    s{(<(\w+:)?EntityDescriptor\b[^>]*?)\s+cacheDuration="[^"]*"}{$1}s;
  ' "${tmp}" > "${METADATA_DIR}/${file}"
  rm -f "${tmp}"
  echo "  -> config/metadata-aggregator/metadata/${file}"
}

refresh_reference() {
  fetch 11010 /saml2/metadata reference-authn-server.xml
}

refresh_test_my_eid() {
  fetch 11020 /testmyeid/metadata test-my-eid.xml
  fetch 11020 /testmyeid/metadata/sign test-my-eid-sign.xml
}

refresh_test_client() {
  fetch 11030 /saml/metadata/sp1 test-client-sp1.xml
  fetch 11030 /saml/metadata/sign1 test-client-sign1.xml
}

services=("$@")
if [[ ${#services[@]} -eq 0 ]]; then
  services=(reference test-my-eid test-client)
fi

mkdir -p "${METADATA_DIR}"

for service in "${services[@]}"; do
  case "${service}" in
    reference) refresh_reference ;;
    test-my-eid) refresh_test_my_eid ;;
    test-client) refresh_test_client ;;
    *)
      echo "Unknown service: ${service}" >&2
      echo "Usage: $0 [reference | test-my-eid | test-client] ..." >&2
      exit 1
      ;;
  esac
done

echo "Done. The metadata aggregator reads the files again within a minute."
