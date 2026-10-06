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
# Generates the keys, key stores and certificates of the local federation.
#
# TEST CREDENTIALS ONLY. Every key generated here is committed to a public repository and offers no protection
# whatsoever. Never use them for anything but the local federation.
#
# Usage: scripts/generate-credentials.sh [all | tls | metadata | federation | oidc | reference | test-my-eid | test-client] ...
#
# Without arguments, everything is generated. Running the script again replaces the files. The trust store in
# config/common is rebuilt whenever the TLS or metadata signing certificate is replaced.
#
# The reference, test-my-eid and test-client targets generate the SAML keys of each service.
#
# The oidc target generates the OpenID Connect keys of the services that need keys of their own: the signing key and
# the RSA encryption key of the reference authentication server, and the keys of the test client: the signing key of
# Test RP 1 and Test RP 2, the RSA encryption key of Test RP 2, and the two EC P-256 signing keys and the EC P-256
# encryption key of Test RP 3 (oidc-keys.jks in their configuration folders). Test my eID uses its SAML keys for
# OpenID Connect.
#
# The federation target generates every OpenID Federation key: the keys of the federation entities (trust anchor,
# trust mark issuers and registration intermediates), and the keys of the reference authentication server,
# test-my-eid and the test client. The public keys of the trust anchor and the trust mark issuers are published in
# config/common, and the public keys of the three services are written into the configuration of the federation
# service (config/openid-federation/application-compose.yml), which puts them in their subordinate statements.
#
# After new SAML keys have been generated for a service, its metadata must be refreshed in the metadata aggregator,
# see scripts/refresh-metadata.sh. After new federation keys, the federation service must be restarted.
#
# Requires keytool (part of any Java JDK, version 17 or later), openssl and perl.
#

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${ROOT}/config"

HOST="local.fed.swedenconnect.se"
PASSWORD="secret"
VALIDITY_DAYS=3650
DN_SUFFIX="OU=TEST ONLY - Local Federation, O=Sweden Connect, C=SE"

FEDERATION_CONFIG="${CONFIG}/openid-federation/application-compose.yml"

if ! command -v keytool > /dev/null; then
  echo "keytool was not found. Install a Java JDK (17 or later) and make sure keytool is in the PATH." >&2
  exit 1
fi
for tool in openssl perl; do
  if ! command -v "${tool}" > /dev/null; then
    echo "${tool} was not found. Install it and make sure it is in the PATH." >&2
    exit 1
  fi
done

#
# Runs keytool, and only shows its output if it fails.
#
run_keytool() {
  local output
  if ! output="$(keytool "$@" 2>&1)"; then
    echo "${output}" >&2
    exit 1
  fi
}

#
# Generates an RSA key pair with a self-signed certificate.
#
# $1 - the key store file
# $2 - the alias
# $3 - the common name of the certificate
# $4 - optional keytool -ext argument
#
genkey() {
  local store="$1" alias="$2" cn="$3" ext="${4:-}"
  local args=(-genkeypair -keystore "${store}" -storetype JKS -storepass "${PASSWORD}" -keypass "${PASSWORD}"
    -alias "${alias}" -keyalg RSA -keysize 3072 -sigalg SHA256withRSA -validity "${VALIDITY_DAYS}"
    -dname "CN=${cn}, ${DN_SUFFIX}")
  if [[ -n "${ext}" ]]; then
    args+=(-ext "${ext}")
  fi
  run_keytool "${args[@]}"
}

#
# Generates an EC key pair with a self-signed certificate.
#
# $1 - the key store file
# $2 - the alias
# $3 - the common name of the certificate
# $4 - the curve, secp256r1 or secp521r1
#
genkey_ec() {
  local store="$1" alias="$2" cn="$3" curve="$4" sigalg
  case "${curve}" in
    secp256r1) sigalg=SHA256withECDSA ;;
    secp521r1) sigalg=SHA512withECDSA ;;
  esac
  run_keytool -genkeypair -keystore "${store}" -storetype JKS -storepass "${PASSWORD}" -keypass "${PASSWORD}" \
    -alias "${alias}" -keyalg EC -groupname "${curve}" -sigalg "${sigalg}" -validity "${VALIDITY_DAYS}" \
    -dname "CN=${cn}, ${DN_SUFFIX}"
}

#
# Base64url-encodes standard input, without padding.
#
b64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

#
# Writes the public key of a P-521 certificate as a JWK, with its RFC 7638 thumbprint as kid. This is the JWK that
# the federation service publishes for the key.
#
# $1 - the certificate file (PEM)
# $2 - the JWK file
#
write_p521_jwk() {
  local tmp x y kid
  tmp="$(mktemp)"
  # The DER-encoded public key ends with the uncompressed point: 0x04, x (66 bytes) and y (66 bytes).
  openssl x509 -in "$1" -pubkey -noout | openssl pkey -pubin -outform DER | tail -c 132 > "${tmp}"
  x="$(head -c 66 "${tmp}" | b64url)"
  y="$(tail -c 66 "${tmp}" | b64url)"
  rm -f "${tmp}"
  kid="$(printf '{"crv":"P-521","kty":"EC","x":"%s","y":"%s"}' "${x}" "${y}" | openssl dgst -sha256 -binary | b64url)"
  printf '{\n  "kty": "EC",\n  "crv": "P-521",\n  "kid": "%s",\n  "x": "%s",\n  "y": "%s"\n}\n' \
    "${kid}" "${x}" "${y}" > "$2"
}

#
# Wraps a JWK in a JWK set.
#
# $1 - the JWK file
# $2 - the JWK set file
#
write_jwks() {
  { printf '{\n  "keys": [\n'; sed 's/^/    /' "$1"; printf '  ]\n}\n'; } > "$2"
}

#
# Writes the public key of a P-521 key in a key store as a JWK set.
#
# $1 - the key store file
# $2 - the alias
# $3 - the JWK set file
#
publish_jwks() {
  local tmp
  tmp="$(mktemp -d)"
  exportcert "$1" "$2" "${tmp}/cert.pem"
  write_p521_jwk "${tmp}/cert.pem" "${tmp}/key.jwk"
  write_jwks "${tmp}/key.jwk" "$3"
  rm -rf "${tmp}"
}

#
# Replaces the public federation key of a service in the configuration of the federation service, that is, the
# lines between "# BEGIN <name>" and "# END <name>" under federation.keys.additional-keys.
#
# $1 - the key name, also used in the markers
# $2 - the certificate file (PEM)
#
update_federation_key() {
  local name="$1" cert="$2"
  NAME="${name}" CERT="$(cat "${cert}")" perl -0777 -i -pe '
    my $name = $ENV{NAME};
    (my $cert = $ENV{CERT}) =~ s/^/          /mg;
    my $entry = "      - name: $name\n        certificate: |\n$cert\n";
    s{(# BEGIN \Q$name\E\n).*?( *# END \Q$name\E\n)}{$1$entry$2}s
      or die "The markers of the key $name were not found\n";
  ' "${FEDERATION_CONFIG}"
}

#
# Generates the OpenID Federation key of a service, an EC P-256 key, and writes its public key into the
# configuration of the federation service.
#
# $1 - the configuration folder of the service, under config, also used as the key name
# $2 - the common name of the certificate
#
generate_service_federation_key() {
  local dir="$1" cn="$2"
  local store="${CONFIG}/${dir}/federation-key.jks"
  rm -f "${store}"
  genkey_ec "${store}" federation "${cn}" secp256r1
  exportcert "${store}" federation "${CONFIG}/${dir}/federation-key.crt"
  update_federation_key "${dir}" "${CONFIG}/${dir}/federation-key.crt"
}

#
# Exports a certificate in PEM format.
#
# $1 - the key store file
# $2 - the alias
# $3 - the certificate file
#
exportcert() {
  run_keytool -exportcert -rfc -keystore "$1" -storepass "${PASSWORD}" -alias "$2" -file "$3"
}

generate_tls() {
  echo "Generating the TLS key store for ${HOST} ..."
  local store="${CONFIG}/common/tls.jks"
  rm -f "${store}"
  genkey "${store}" tls "${HOST}" "SAN=DNS:${HOST},DNS:localhost,IP:127.0.0.1"
  exportcert "${store}" tls "${CONFIG}/common/tls.crt"
}

generate_metadata() {
  echo "Generating the metadata signing key of the metadata aggregator ..."
  local store="${CONFIG}/metadata-aggregator/metadata-signing.jks"
  rm -f "${store}"
  genkey "${store}" metadata "Local Federation Metadata Signing"
  exportcert "${store}" metadata "${CONFIG}/common/metadata-signing.crt"
}

generate_truststore() {
  echo "Building the trust store ..."
  local store="${CONFIG}/common/trust.jks"
  rm -f "${store}"
  run_keytool -importcert -noprompt -keystore "${store}" -storetype JKS -storepass "${PASSWORD}" \
    -alias tls -file "${CONFIG}/common/tls.crt"
  run_keytool -importcert -noprompt -keystore "${store}" -storetype JKS -storepass "${PASSWORD}" \
    -alias metadata-signing -file "${CONFIG}/common/metadata-signing.crt"
}

generate_federation() {
  echo "Generating the federation keys of the OpenID Federation entities ..."
  local store="${CONFIG}/openid-federation/federation-keys.jks"
  rm -f "${store}"
  genkey_ec "${store}" trustanchor "Local Federation Trust Anchor" secp521r1
  genkey_ec "${store}" tmi-loa "Local Federation Level of Assurance Trust Mark Issuer" secp521r1
  genkey_ec "${store}" tmi-contracts "Local Federation Contracts Trust Mark Issuer" secp521r1
  genkey_ec "${store}" im-reg-sc "Local Federation RP Registration Intermediate" secp521r1
  genkey_ec "${store}" im-reg-sc-op "Local Federation OP Registration Intermediate" secp521r1

  echo "Publishing the public key of the trust anchor in config/common ..."
  local cert="${CONFIG}/common/oidf-trust-anchor.crt"
  exportcert "${store}" trustanchor "${cert}"
  openssl x509 -in "${cert}" -pubkey -noout > "${CONFIG}/common/oidf-trust-anchor.pem"
  write_p521_jwk "${cert}" "${CONFIG}/common/oidf-trust-anchor.jwk"
  write_jwks "${CONFIG}/common/oidf-trust-anchor.jwk" "${CONFIG}/common/oidf-trust-anchor.jwks"

  echo "Publishing the public keys of the trust mark issuers in config/common ..."
  publish_jwks "${store}" tmi-loa "${CONFIG}/common/oidf-tmi-loa.jwks"
  publish_jwks "${store}" tmi-contracts "${CONFIG}/common/oidf-tmi-contracts.jwks"

  echo "Generating the federation keys of the reference authentication server, test-my-eid and the test client ..."
  generate_service_federation_key reference-authn-server "Reference Authentication Server Federation Key"
  generate_service_federation_key test-my-eid "Test my eID Federation Key"
  generate_service_federation_key test-client "Test Client Federation Key"
}

generate_reference() {
  echo "Generating the SAML keys of the reference authentication server ..."
  local store="${CONFIG}/reference-authn-server/saml-keys.jks"
  rm -f "${store}"
  genkey "${store}" saml-sign "Reference Authentication Server SAML Signing"
  genkey "${store}" saml-encrypt "Reference Authentication Server SAML Encryption"
}

generate_test_my_eid() {
  echo "Generating the SAML keys of test-my-eid ..."
  local store="${CONFIG}/test-my-eid/sp-keys.jks"
  rm -f "${store}"
  genkey "${store}" sign "Test my eID SAML Signing"
  genkey "${store}" encrypt "Test my eID SAML Encryption"
  genkey "${store}" metadata-sign "Test my eID Metadata Signing"
}

generate_oidc() {
  echo "Generating the OpenID Connect signing and encryption keys of the reference authentication server ..."
  local store="${CONFIG}/reference-authn-server/oidc-keys.jks"
  rm -f "${store}"
  genkey "${store}" oidc-sign "Reference Authentication Server OIDC Signing"
  genkey "${store}" oidc-encrypt "Reference Authentication Server OIDC Encryption"

  echo "Generating the OpenID Connect signing and encryption keys of the test client ..."
  store="${CONFIG}/test-client/oidc-keys.jks"
  rm -f "${store}"
  genkey "${store}" oidc-sign "Test Client OIDC Signing"
  genkey "${store}" oidc-encrypt "Test Client OIDC Encryption"
  genkey_ec "${store}" oidc-ec-sign "Test Client OIDC EC Signing 1" secp256r1
  genkey_ec "${store}" oidc-ec-sign2 "Test Client OIDC EC Signing 2" secp256r1
  genkey_ec "${store}" oidc-ec-encrypt "Test Client OIDC EC Encryption" secp256r1
}

generate_test_client() {
  echo "Generating the SAML keys of the test client ..."
  local store="${CONFIG}/test-client/sp-keys.jks"
  rm -f "${store}"
  genkey "${store}" sign "Test Client SAML Signing"
  genkey "${store}" encrypt "Test Client SAML Encryption"
}

targets=("$@")
if [[ ${#targets[@]} -eq 0 ]]; then
  targets=(all)
fi

rebuild_trust=false
for target in "${targets[@]}"; do
  case "${target}" in
    all)
      generate_tls
      generate_metadata
      generate_federation
      generate_oidc
      generate_reference
      generate_test_my_eid
      generate_test_client
      rebuild_trust=true
      ;;
    tls)
      generate_tls
      rebuild_trust=true
      ;;
    metadata)
      generate_metadata
      rebuild_trust=true
      ;;
    federation)
      generate_federation
      ;;
    oidc)
      generate_oidc
      ;;
    reference)
      generate_reference
      ;;
    test-my-eid)
      generate_test_my_eid
      ;;
    test-client)
      generate_test_client
      ;;
    *)
      echo "Unknown target: ${target}" >&2
      echo "Usage: $0 [all | tls | metadata | federation | oidc | reference | test-my-eid | test-client] ..." >&2
      exit 1
      ;;
  esac
done

if [[ "${rebuild_trust}" == "true" ]]; then
  generate_truststore
fi

echo "Done. The password of every key store and key is '${PASSWORD}'."
