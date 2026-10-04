![Logo](https://raw.githubusercontent.com/swedenconnect/technical-framework/master/img/sweden-connect.png)

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

# Services of the Local Federation

This is the reference for the services in [docker-compose.yml](../docker-compose.yml): what each service is for, its ports, URLs and configuration folder. How to set up the federation is described in [Setting up the local federation](setup.md), and the OpenID Federation in [OpenID Federation in the Local Federation](openid-federation.md).

All services are reached through the host name `local.fed.swedenconnect.se`, which you map to `127.0.0.1` in your hosts file. The containers reach each other through the same host name, so every URL below works both from your browser and from the services themselves. All HTTPS endpoints use the same self-signed certificate, see [Keys and certificates](#keys-and-certificates).

- [Port ranges](#port-ranges)
- [Base services](#base-services)
  - [Redis](#redis)
- [Applications](#applications)
  - [Metadata aggregator](#metadata-aggregator)
  - [Sweden Connect reference authentication server](#reference-authn-server)
  - [Test my eID](#test-my-eid)
  - [Sweden Connect test client](#test-client)
  - [OpenID Federation](#openid-federation)
- [Keys and certificates](#keys-and-certificates)

<a name="port-ranges"></a>
## Port ranges

The ports do not overlap with those of Sweden Connect's internal local environment, so both can run at the same time.

| Range | Used for |
| :--- | :--- |
| `10900-10999` | Base services that the applications use, such as Redis. |
| `11000-` | Applications, in blocks of ten ports each. |

| Ports | Service |
| :--- | :--- |
| `10900-10901` | [Redis](#redis) |
| `11000-11009` | [Metadata aggregator](#metadata-aggregator) |
| `11010-11019` | [Sweden Connect reference authentication server](#reference-authn-server) |
| `11020-11029` | [Test my eID](#test-my-eid) |
| `11030-11039` | [Sweden Connect test client](#test-client) |
| `11040-11049` | [OpenID Federation](#openid-federation) |

---

<a name="base-services"></a>
## Base services

<a name="redis"></a>
### Redis

A [Redis Stack](https://redis.io/docs/latest/operate/oss_and_stack/) server, without TLS, protected by a password. The reference authentication server keeps its HTTP sessions, single sign-on state and stores in it.

**Ports:**

- `10900` – The Redis server.
- `10901` – [RedisInsight](https://redis.io/insight/), a web interface for browsing the data.

**URLs:**

- `local.fed.swedenconnect.se:10900` – The Redis server. The password is `supersecret`, unless you set `REDIS_PASSWORD` in `.env`.
- http://local.fed.swedenconnect.se:10901 – RedisInsight. If it does not list the database, add one with host `localhost`, port `6379` and the password above.

**Configuration folder:** None. The password is set by `REDIS_PASSWORD`, see [.env.example](../.env.example).

The services inside Docker Compose reach Redis as `redis:6379`. An application that shares this Redis must use key names of its own. The reference authentication server writes all its keys under the prefix `reference-authn-server`.

---

<a name="applications"></a>
## Applications

<a name="metadata-aggregator"></a>
### Metadata aggregator

Publishes the SAML metadata of the federation: one feed, signed with the federation's metadata signing key, holding the metadata of every Identity Provider and Service Provider in the federation. Every other service downloads its metadata from here. The image is `ghcr.io/swedenconnect/metadata-aggregator`.

**Port range:** `11000-11009`

**Ports:**

- `11000` – HTTPS.

**URLs:**

- https://local.fed.swedenconnect.se:11000/metadata/feed – Every entity of the federation.
- https://local.fed.swedenconnect.se:11000/metadata/mdx/role/idp.xml – The Identity Providers.
- https://local.fed.swedenconnect.se:11000/metadata/mdx/role/sp.xml – The Service Providers.

**Configuration folder:** [config/metadata-aggregator](../config/metadata-aggregator)

**Configuration details:**

- The feed is built from the entity metadata files in [config/metadata-aggregator/metadata](../config/metadata-aggregator/metadata), one file per entity. The aggregator reads the files again every minute.
- To add your own Service Provider or Identity Provider to the federation, put its metadata in a file of its own in that folder, see [Adding your own service](setup.md#adding-your-own-service).
- The feed is signed with the key in `metadata-signing.jks`. The certificate that validates the signature is [config/common/metadata-signing.crt](../config/common/metadata-signing.crt).
- The feed has a `cacheDuration` of ten minutes and is valid for seven days.

---

<a name="reference-authn-server"></a>
### Sweden Connect reference authentication server

The [Sweden Connect reference authentication server](https://github.com/swedenconnect/spring-authentication-server/tree/main/sweden-connect-reference), a SAML Identity Provider and OpenID Provider built on the [Spring Authentication Server](https://docs.swedenconnect.se/spring-authentication-server/). The authentication is simulated: you pick a person from a list instead of authenticating, while everything around the authentication follows the [Swedish eID Framework](https://docs.swedenconnect.se/technical-framework/) as a production Identity Provider does. It also serves signature services.

The OpenID Provider is a member of the [OpenID Federation](openid-federation.md#registered-services). It accepts every Relying Party that the federation resolves, without requiring any trust marks of it.

**Port range:** `11010-11019`

**Ports:**

- `11010` – HTTPS.
- `11011` – Spring Boot Actuator (HTTPS).

**SAML entityID:** `https://local.fed.swedenconnect.se/idp`

**OpenID Connect issuer and OpenID Federation entity identifier:** `https://local.fed.swedenconnect.se:11010`

**URLs:**

- https://local.fed.swedenconnect.se:11010/saml2/metadata – The SAML metadata of the Identity Provider.
- https://local.fed.swedenconnect.se:11010/.well-known/openid-configuration – The discovery document of the OpenID Provider.
- https://local.fed.swedenconnect.se:11010/.well-known/openid-federation – The entity configuration of the OpenID Provider, with its trust marks.
- https://local.fed.swedenconnect.se:11010/oidc/authorize – The authorization endpoint.
- https://local.fed.swedenconnect.se:11010/oidc/token – The token endpoint.
- https://local.fed.swedenconnect.se:11010/oidc/userinfo – The UserInfo endpoint.
- https://local.fed.swedenconnect.se:11010/oidc/jwks – The JWK set of the OpenID Provider.
- https://local.fed.swedenconnect.se:11011/actuator – The Actuator. These endpoints are exposed:
  - https://local.fed.swedenconnect.se:11011/actuator/health – Health, with details. It also reports the SAML metadata that the server has downloaded, the Redis connection, the trust marks of the OpenID Provider (`oidc-trust-marks`) and the calls to the federation (`oidc-federation`).
  - https://local.fed.swedenconnect.se:11011/actuator/info – The version and configuration summary of the server.
  - https://local.fed.swedenconnect.se:11011/actuator/auditevents – The audit events kept in memory.
  - https://local.fed.swedenconnect.se:11011/actuator/clients – The Service Providers and OpenID Connect clients that the server knows. The update operations are allowed, see [Monitoring and managing the server](https://docs.swedenconnect.se/spring-authentication-server/management.html#the-clients-endpoint).

**Configuration folder:** [config/reference-authn-server](../config/reference-authn-server)

**Configuration details:**

- The image is set by `REFERENCE_AUTHN_SERVER_IMAGE` in `.env`, see [Using a local build of the reference authentication server](setup.md#local-build).
- [application-compose.yml](../config/reference-authn-server/application-compose.yml) supplies what the default configuration of the service leaves to the deployment. It is read with the Spring profile `compose`. The settings are described in the [README of the service](https://github.com/swedenconnect/spring-authentication-server/tree/main/sweden-connect-reference).
- The SAML signing and encryption keys are in `saml-keys.jks`.
- **OpenID Connect:** the OpenID Connect signing key is in `oidc-keys.jks`, and the federation key that signs the entity configuration in `federation-key.jks`, see [OpenID Federation in the Local Federation](openid-federation.md#registered-services).
- The OpenID Provider is registered under the OP Registration Intermediate `im-reg-sc-op`. It fetches its trust marks, `loa2`, `loa3` and `loa4` from `tmi-loa` and both contract trust marks from `tmi-contracts`, and verifies them with the keys of the issuers in `config/common/oidf-tmi-loa.jwks` and `config/common/oidf-tmi-contracts.jwks`.
- Its clients are resolved through the federation, at the resolve endpoint of the trust anchor, verified with the key in `config/common/oidf-trust-anchor.jwks`. No clients are configured in the server itself.
- The OpenID Connect codes, tokens, federation cache and trust marks are kept in [Redis](#redis), like the rest of its state.
- The Service Provider metadata is downloaded from the metadata aggregator, and validated with the aggregator's certificate. A copy is kept in `cache/`, which is git-ignored.
- The HTTP sessions, single sign-on state and stores are kept in [Redis](#redis).
- Audit events are kept in memory, where the `auditevents` endpoint reads them, and written to `audit/audit.log`, one JSON event per line. The file is rolled daily: the events of earlier days are moved to `audit-<yyyyMMdd>.log`. The `audit` folder is git-ignored. See [Auditing](https://docs.swedenconnect.se/spring-authentication-server/audit.html) for the events.
- The simulated users are those of the service. To use other users, put a `users.yml` in the configuration folder and set the environment variable `IDP_CONFIG_DIR` of the service to `/opt/reference-authn-server`, see [The simulated users](https://github.com/swedenconnect/spring-authentication-server/tree/main/sweden-connect-reference#the-simulated-users).

---

<a name="test-my-eid"></a>
### Test my eID

[Test my eID](https://github.com/swedenconnect/test-my-eid) is a Service Provider that lets a user log in with any Identity Provider of the federation and shows the attributes it received. After a login, the user can also sign a test message through the simulated signature service that is part of the application, which has an entityID of its own.

It is also an OpenID Connect Relying Party that is a member of the [OpenID Federation](openid-federation.md#registered-services). It lists the OpenID Providers of the federation on its start page, next to the SAML Identity Providers, and offers signature approval after an OpenID Connect login.

**Port range:** `11020-11029`

**Ports:**

- `11020` – HTTPS.

**SAML entityIDs:**

- `https://local.fed.swedenconnect.se/testmyeid` – The Service Provider.
- `https://local.fed.swedenconnect.se/testmyeid-sign` – The simulated signature service.

**URLs:**

- https://local.fed.swedenconnect.se:11020/testmyeid – The start page, listing the Identity Providers of the federation.
- https://local.fed.swedenconnect.se:11020/testmyeid/metadata – The metadata of the Service Provider.
- https://local.fed.swedenconnect.se:11020/testmyeid/metadata/sign – The metadata of the simulated signature service.
- https://local.fed.swedenconnect.se:11020/testmyeid/.well-known/openid-federation – The entity configuration of the Relying Party.
- https://local.fed.swedenconnect.se:11020/testmyeid/oidc/metadata – The metadata of the Relying Party as JSON.

**Configuration folder:** [config/test-my-eid](../config/test-my-eid)

**Configuration details:**

- The image is set by `TEST_MY_EID_IMAGE` in `.env`, see [Using a local build of Test my eID](setup.md#test-my-eid-build).
- [application-compose.yml](../config/test-my-eid/application-compose.yml) is read with the Spring profile `compose`. The settings are described in the [README of Test my eID](https://github.com/swedenconnect/test-my-eid#configuration-settings).
- The SAML signing, encryption and metadata signing keys are in `sp-keys.jks`.
- **OpenID Connect:** the Relying Party has the entity identifier and client ID `https://local.fed.swedenconnect.se:11020/testmyeid`, and is registered under the RP Registration Intermediate `im-reg-sc`. It uses the SAML signing and encryption keys for OpenID Connect.
- The federation key that signs its entity configuration is in `federation-key.jks`, see [OpenID Federation in the Local Federation](openid-federation.md#registered-services).
- It trusts the trust anchor with the key in `config/common/oidf-trust-anchor.jwks`, finds the OpenID Providers through `im-reg-sc-op`, and fetches the trust mark `https://id.swedenconnect.se/contract/sc/eid-authorization-system` from `tmi-contracts`.
- Every Identity Provider of the metadata feed is offered on the start page.

---

<a name="test-client"></a>
### Sweden Connect test client

The [Sweden Connect test client](https://github.com/swedenconnect/sweden-connect-test-client) lets you build SAML authentication requests in detail, send them to an Identity Provider and inspect the response and assertion. It acts as two Service Providers: an ordinary Service Provider and a signature service.

It is also an OpenID Connect Relying Party, Test RP 1, that is a member of the [OpenID Federation](openid-federation.md#registered-services). It finds the OpenID Providers through the OP Registration Intermediate and resolves them at the trust anchor.

**Port range:** `11030-11039`

**Ports:**

- `11030` – HTTPS.

**SAML entityIDs:**

- `https://local.fed.swedenconnect.se/test-client/sp1` – Test SP 1, for authentication with a personal identity number.
- `https://local.fed.swedenconnect.se/test-client/sign1` – Test SignService 1, a signature service.

**URLs:**

- https://local.fed.swedenconnect.se:11030 – The user interface.
- https://local.fed.swedenconnect.se:11030/saml/metadata/sp1 – The metadata of Test SP 1.
- https://local.fed.swedenconnect.se:11030/saml/metadata/sign1 – The metadata of Test SignService 1.
- https://local.fed.swedenconnect.se:11030/testrp1/.well-known/openid-federation – The entity configuration of Test RP 1.
- https://local.fed.swedenconnect.se:11030/oidc/federation/info – The federation status of the test client: its Relying Party with its trust marks, and the OpenID Providers found in the federation.

**Configuration folder:** [config/test-client](../config/test-client)

**Configuration details:**

- [application-compose.yml](../config/test-client/application-compose.yml) is read with the Spring profile `compose`. The settings are described in [Configuration and Deployment](https://github.com/swedenconnect/sweden-connect-test-client/blob/main/docs/configuration.md).
- The SAML signing and encryption keys of both Service Providers are in `sp-keys.jks`. The keys that are built into the test client, for testing other key types and sizes, are also available and can be selected in its configuration.
- The Identity Provider metadata is downloaded from the metadata aggregator. A copy is kept in `cache/`, which is git-ignored.
- **OpenID Connect:** Test RP 1 has the entity identifier and client ID `https://local.fed.swedenconnect.se:11030/testrp1`, and is registered under the RP Registration Intermediate `im-reg-sc`. It authenticates at the token endpoint with `private_key_jwt`.
- Its OpenID Connect signing key is in `oidc-keys.jks`, and the federation key that signs its entity configuration in `federation-key.jks`, see [OpenID Federation in the Local Federation](openid-federation.md#registered-services).
- It trusts the trust anchor with the key in `config/common/oidf-trust-anchor.jwks`, and fetches the trust mark `https://id.swedenconnect.se/contract/sc/eid-authorization-system` from `tmi-contracts`.

---

<a name="openid-federation"></a>
### OpenID Federation

The [OpenID Federation service](https://github.com/swedenconnect/openid-federation-services) hosts all entities of the local OpenID Federation: the trust anchor, which is also the resolver, the two trust mark issuers and the two registration intermediates. The federation is built like the Sweden Connect OpenID Federation, and is described in [OpenID Federation in the Local Federation](openid-federation.md).

**Port range:** `11040-11049`

**Ports:**

- `11040` – HTTPS, every federation entity.
- `11041` – Spring Boot Actuator (HTTPS).

**Entities:**

- `https://local.fed.swedenconnect.se:11040/trustanchor` – The trust anchor and resolver.
- `https://local.fed.swedenconnect.se:11040/tmi-loa` – The Level of Assurance Trust Mark Issuer.
- `https://local.fed.swedenconnect.se:11040/tmi-contracts` – The Contracts Trust Mark Issuer.
- `https://local.fed.swedenconnect.se:11040/im-reg-sc` – The RP Registration Intermediate.
- `https://local.fed.swedenconnect.se:11040/im-reg-sc-op` – The OP Registration Intermediate.

**URLs:**

- https://local.fed.swedenconnect.se:11040/trustanchor/.well-known/openid-federation – The entity configuration of the trust anchor. The entity configuration of every entity is at `<entity identifier>/.well-known/openid-federation`.
- https://local.fed.swedenconnect.se:11040/trustanchor/subordinate_listing – The subordinates of the trust anchor.
- https://local.fed.swedenconnect.se:11040/trustanchor/fetch?sub= – The subordinate statements of the trust anchor.
- https://local.fed.swedenconnect.se:11040/trustanchor/resolve?sub=&trust_anchor=https://local.fed.swedenconnect.se:11040/trustanchor – The resolve endpoint.
- https://local.fed.swedenconnect.se:11040/trustanchor/discovery?trust_anchor=https://local.fed.swedenconnect.se:11040/trustanchor – The entities of the federation.
- https://local.fed.swedenconnect.se:11040/im-reg-sc/subordinate_listing – The registered Relying Parties.
- https://local.fed.swedenconnect.se:11040/im-reg-sc-op/subordinate_listing – The registered OpenID Providers.
- https://local.fed.swedenconnect.se:11040/tmi-loa/trust_mark?trust_mark_type=&sub= – Issues a level of assurance trust mark. The other trust mark endpoints of both issuers are listed in [Entities and endpoints](openid-federation.md#entities-and-endpoints).
- https://local.fed.swedenconnect.se:11041/actuator – The Actuator. All endpoints are exposed, among them:
  - https://local.fed.swedenconnect.se:11041/actuator/health – Health.
  - https://local.fed.swedenconnect.se:11041/actuator/ready – Whether the service is ready to serve requests.
  - https://local.fed.swedenconnect.se:11041/actuator/info – The version of the service.

**Configuration folder:** [config/openid-federation](../config/openid-federation)

**Configuration details:**

- The image is set by `OPENID_FEDERATION_IMAGE` in `.env`, see [Using another image of the OpenID Federation service](setup.md#federation-image).
- [application-compose.yml](../config/openid-federation/application-compose.yml) holds the settings of the service, and is read with the Spring profile `compose`. The settings are described in [Service Configuration](https://github.com/swedenconnect/openid-federation-services/blob/main/docs/service-configuration.md).
- The entities, the trust anchor and intermediates with their subordinates, the trust mark issuers and the resolver are read from the JSON files in the folder when the service starts, see [The configuration files](openid-federation.md#configuration-files). After a change, restart the service with `docker compose restart openid-federation`.
- The federation keys of the federation entities are in `federation-keys.jks`, one EC P-521 key per entity. The public key of the trust anchor is published in `config/common`, see [The trust anchor key](openid-federation.md#trust-anchor-key).
- The state is kept in memory. Tracing is turned off.

---

<a name="keys-and-certificates"></a>
## Keys and certificates

All keys, key stores and certificates are test credentials, committed so that a fresh clone runs without extra steps. The password of every key store and key is `secret`. [scripts/generate-credentials.sh](../scripts/generate-credentials.sh) generates them, see [Regenerating keys and certificates](setup.md#regenerating-keys).

| File | Contents |
| :--- | :--- |
| `config/common/tls.jks` | The TLS key and self-signed certificate for `local.fed.swedenconnect.se`, alias `tls`, used by every service. |
| `config/common/tls.crt` | The TLS certificate in PEM format. |
| `config/common/trust.jks` | The trust store of every Java service: the TLS certificate and the metadata signing certificate. |
| `config/common/metadata-signing.crt` | The certificate that validates the signature of the metadata feed. |
| `config/metadata-aggregator/metadata-signing.jks` | The metadata signing key of the aggregator, alias `metadata`. |
| `config/reference-authn-server/saml-keys.jks` | The SAML keys of the reference authentication server, aliases `saml-sign` and `saml-encrypt`. |
| `config/test-my-eid/sp-keys.jks` | The SAML keys of Test my eID, aliases `sign`, `encrypt` and `metadata-sign`. |
| `config/test-client/sp-keys.jks` | The SAML keys of the test client, aliases `sign` and `encrypt`. |
| `config/openid-federation/federation-keys.jks` | The federation keys of the OpenID Federation entities, aliases `trustanchor`, `tmi-loa`, `tmi-contracts`, `im-reg-sc` and `im-reg-sc-op`. |
| `config/common/oidf-trust-anchor.pem`, `.jwk`, `.jwks` and `.crt` | The public key of the trust anchor as a PEM public key, a JWK, a JWK set and a certificate. |
| `config/common/oidf-tmi-loa.jwks`, `oidf-tmi-contracts.jwks` | The public keys of the two trust mark issuers as JWK sets. |
| `config/reference-authn-server/oidc-keys.jks` | The OpenID Connect signing key of the reference authentication server, alias `oidc-sign`. |
| `config/test-client/oidc-keys.jks` | The OpenID Connect signing key of the test client's Test RP 1, alias `oidc-sign`. |
| `config/reference-authn-server/federation-key.jks` | The OpenID Federation key of the reference authentication server, alias `federation`. Its certificate is `federation-key.crt`. |
| `config/test-my-eid/federation-key.jks` | The OpenID Federation key of Test my eID, alias `federation`. Its certificate is `federation-key.crt`. |
| `config/test-client/federation-key.jks` | The OpenID Federation key of the test client's Test RP 1, alias `federation`. Its certificate is `federation-key.crt`. |

---

Copyright &copy; 2026, [Sweden Connect](https://www.swedenconnect.se). Licensed under version 2.0 of the [Apache License](http://www.apache.org/licenses/LICENSE-2.0).
