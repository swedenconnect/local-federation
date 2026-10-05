![Logo](https://raw.githubusercontent.com/swedenconnect/technical-framework/master/img/sweden-connect.png)

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

# Setting up the Local Federation

This walkthrough takes you from a fresh clone of the repository to a first login through the Sweden Connect reference authentication server, which is both a SAML Identity Provider and an OpenID Provider. The services themselves, with their ports and URLs, are described in [Services](services.md), and the OpenID Federation, with how to register your own services in it, in [OpenID Federation in the Local Federation](openid-federation.md).

- [Prerequisites](#prerequisites)
- [Starting and stopping](#starting-and-stopping)
- [Accepting the TLS certificate](#accepting-the-tls-certificate)
- [A first login from Test my eID](#first-login-test-my-eid)
- [A first login from the test client](#first-login-test-client)
- [An OpenID Connect login from the test client](#oidc-login-test-client)
- [An OpenID Connect login from Test my eID](#oidc-login-test-my-eid)
- [Audit entries and the Actuator](#audit-and-actuator)
- [Using a local build of the reference authentication server](#local-build)
- [Using a local build of Test my eID](#test-my-eid-build)
- [Using another image of the OpenID Federation service](#federation-image)
- [Adding your own service](#adding-your-own-service)
- [Regenerating keys and certificates](#regenerating-keys)
- [Refreshing the metadata](#refreshing-metadata)

<a name="prerequisites"></a>
## Prerequisites

### Docker

[Docker Desktop](https://www.docker.com/products/docker-desktop/), or Docker Engine with the Compose plugin, version 20.10 or later. The services use about 2 GB of memory together.

### The hosts file

All services are reached through the host name `local.fed.swedenconnect.se`. Add it to your hosts file, `/etc/hosts` on macOS and Linux, or `C:\Windows\System32\drivers\etc\hosts` on Windows:

```
#
# Sweden Connect local federation
#
127.0.0.1       local.fed.swedenconnect.se
```

The containers reach each other through the same host name. Docker Compose maps it to your machine inside each container, so you do not need to do anything more for that.

### Access to GitHub's container registry

The Sweden Connect images are pulled from GitHub's container registry, `ghcr.io`. They are public, so normally no login is needed. If a pull is denied, log in with your GitHub user and a [personal access token](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-to-the-container-registry) with the `read:packages` scope:

```bash
echo $GITHUB_ACCESS_TOKEN | docker login ghcr.io -u $GITHUB_USER --password-stdin
```

### The `.env` file

Compose reads its variables from a `.env` file next to `docker-compose.yml`. It is git-ignored, and you only need it to change a default. [.env.example](../.env.example) lists every variable with its default:

| Variable | Description | Default |
| :--- | :--- | :--- |
| `REFERENCE_AUTHN_SERVER_IMAGE` | The image of the reference authentication server. | `ghcr.io/swedenconnect/sweden-connect-reference-authn-server:latest` |
| `TEST_MY_EID_IMAGE` | The image of Test my eID. | `ghcr.io/swedenconnect/test-my-eid:4.0.0` |
| `OPENID_FEDERATION_IMAGE` | The image of the OpenID Federation service. | `ghcr.io/swedenconnect/openid-federation-services:latest` |
| `REDIS_PASSWORD` | The password of Redis. | `supersecret` |

To create one, copy the example and edit it:

```bash
cp .env.example .env
```

> Until the reference authentication server image is published on `ghcr.io`, build it yourself and point `REFERENCE_AUTHN_SERVER_IMAGE` at the local image, see [Using a local build of the reference authentication server](#local-build).

### Tools for the scripts

Only needed if you regenerate keys or refresh metadata: `keytool` from a Java JDK (17 or later), `openssl`, `curl` and `perl`.

<a name="starting-and-stopping"></a>
## Starting and stopping

Run all commands from the root of the repository.

```bash
# Get the latest images
docker compose pull

# Start the federation in the background
docker compose up -d

# Follow the state of the services until all are "healthy"
docker compose ps

# Follow the log of a service
docker compose logs -f reference-authn-server

# Stop the federation and remove the containers
docker compose down
```

The metadata aggregator starts first. The other services wait until it is healthy, and the reference authentication server also waits for Redis. The OpenID Federation service starts on its own. The first start takes a minute or two.

After all services report healthy, it takes up to about half a minute before OpenID Connect logins work. The OpenID Federation service starts before the reference authentication server, Test my eID and the test client, so it cannot read their entity configurations at first. It reads them again every 15 seconds. The reference authentication server and Test my eID try a failed federation lookup again after 15 seconds, and the test client makes its first lookup 30 seconds after it starts.

With a locally built image of the reference authentication server, `docker compose pull` fails for that service, since the image is not in a registry. Pull the others with `docker compose pull --ignore-pull-failures`.

When everything runs, open the [start page](start-page.html) in your browser. It links to every service.

<a name="accepting-the-tls-certificate"></a>
## Accepting the TLS certificate

All services use one self-signed TLS certificate for `local.fed.swedenconnect.se`, [config/common/tls.crt](../config/common/tls.crt). Your browser does not trust it, so it shows a warning the first time you open a service.

Accept the certificate **before** you log in. A login moves your browser between several services, and if one of them has a certificate the browser has not accepted, the login stops halfway with a certificate error. Open each of these and accept the warning:

- https://local.fed.swedenconnect.se:11000/metadata/feed
- https://local.fed.swedenconnect.se:11010/saml2/metadata
- https://local.fed.swedenconnect.se:11020/testmyeid
- https://local.fed.swedenconnect.se:11030
- https://local.fed.swedenconnect.se:11040/trustanchor/subordinate_listing

Instead of accepting it per service, you can make your machine trust the certificate. On macOS:

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain config/common/tls.crt
```

On Windows, import `tls.crt` into "Trusted Root Certification Authorities" with the certificate manager (`certmgr.msc`). Firefox uses a trust store of its own, see its settings under "Certificates". Remove the certificate again when you no longer use the local federation, or after you have [regenerated it](#regenerating-keys).

<a name="first-login-test-my-eid"></a>
## A first login from Test my eID

1. Open https://local.fed.swedenconnect.se:11020/testmyeid.
2. Click "Sweden Connect Reference IdP".
3. The reference authentication server shows its user picker. Select a person, keep the suggested level of assurance and click "Authenticate".
4. Test my eID shows the attributes it received about the person.
5. Click "Sign using Sweden Connect Reference IdP" to try a signature. The reference authentication server now shows the message to sign. Click "Sign", and Test my eID shows the result of the signature.

Under "Advanced" in the user picker you can add a person of your own, and under "Simulate Error" you can send an error back to the Service Provider instead of authenticating.

<a name="first-login-test-client"></a>
## A first login from the test client

1. Open https://local.fed.swedenconnect.se:11030 and select the "SAML" tab.
2. Under "Act as Service Provider ...", select `https://local.fed.swedenconnect.se/test-client/sp1`.
3. Under "Select Identity Provider", select `https://local.fed.swedenconnect.se/idp` and click "Next".
4. The test client shows the authentication request it is about to send. Change what you want to test, or keep the defaults, and click "Send AuthnRequest".
5. Select a person in the reference authentication server and click "Authenticate".
6. The test client shows the response and the assertion, with buttons to view the SAML messages.

Select `https://local.fed.swedenconnect.se/test-client/sign1` in step 2 to act as a signature service instead.

<a name="oidc-login-test-client"></a>
## An OpenID Connect login from the test client

The reference authentication server is also an OpenID Provider in the [OpenID Federation](openid-federation.md). The test client finds it through the federation, and its Relying Party is resolved by the OpenID Provider in the same way, so nothing needs to be registered by hand.

1. Open https://local.fed.swedenconnect.se:11030 and select the "OpenID Connect" tab.
2. Under "Act as Relying Party ...", select `https://local.fed.swedenconnect.se:11030/testrp1`.
3. Under "Select OpenId Provider", select `https://local.fed.swedenconnect.se:11010` and click "Next".
4. The test client shows the authentication request it is about to send. The scope is only `openid` by default. Add `https://id.oidc.se/scope/naturalPersonNumber` and `https://id.oidc.se/scope/naturalPersonInfo` to the scope to get the personal identity number and name of the user. To ask for a level of assurance, add it under "ACR values", for example `http://id.elegnamnden.se/loa/1.0/loa4`. Click "Send request".
5. Select a person in the reference authentication server, and a level of assurance (`loa2`, `loa3` or `loa4`), and click "Authenticate".
6. The test client exchanges the code at the token endpoint, calls the UserInfo endpoint, and shows the ID token, the access token and the UserInfo response with the released claims.

If the reference OpenID Provider is not in the list, the test client has not yet found it in the federation. It makes its first lookup 30 seconds after it starts, and then looks again every ten minutes, or at once after `curl --cacert config/common/tls.crt -X POST https://local.fed.swedenconnect.se:11030/oidc/federation/refresh`. https://local.fed.swedenconnect.se:11030/oidc/federation/info shows what the test client has found.

<a name="oidc-login-test-my-eid"></a>
## An OpenID Connect login from Test my eID

Test my eID lists the OpenID Providers of the federation on its start page next to the SAML Identity Providers, marked "OpenID Connect".

1. Open https://local.fed.swedenconnect.se:11020/testmyeid.
2. Click "Sweden Connect Reference OP".
3. Select a person in the reference authentication server and click "Authenticate".
4. Test my eID shows the claims it received, and the level of assurance.
5. Click "Sign using Sweden Connect Reference OP" to try a signature approval. The reference authentication server shows the message to sign. Click "Sign", and Test my eID shows the result.

<a name="audit-and-actuator"></a>
## Audit entries and the Actuator

The reference authentication server writes an audit event for every step of a login, and for changes of the Service Providers it knows. The events are written to [config/reference-authn-server/audit/audit.log](../config/reference-authn-server/audit), one JSON event per line, on your machine:

```bash
tail -f config/reference-authn-server/audit/audit.log
```

The file is rolled daily; the events of earlier days are moved to `audit-<yyyyMMdd>.log`. The folder is git-ignored. The events are described in [Auditing](https://docs.swedenconnect.se/spring-authentication-server/audit.html).

The Actuator of the reference authentication server answers on port `11011`:

- https://local.fed.swedenconnect.se:11011/actuator/health – The health of the server, including the SAML metadata it has downloaded and the Redis connection.
- https://local.fed.swedenconnect.se:11011/actuator/info – The version and configuration summary of the server.
- https://local.fed.swedenconnect.se:11011/actuator/auditevents – The latest audit events, read from memory.
- https://local.fed.swedenconnect.se:11011/actuator/clients – The Service Providers that the server knows.

The `clients` endpoint also accepts updates. This makes the server download the Service Provider metadata again right away:

```bash
curl --cacert config/common/tls.crt -X POST -H "Content-Type: application/json" \
  https://local.fed.swedenconnect.se:11011/actuator/clients/saml
```

See [Monitoring and managing the server](https://docs.swedenconnect.se/spring-authentication-server/management.html) for all operations.

<a name="local-build"></a>
## Using a local build of the reference authentication server

To run a version of the reference authentication server that you have built yourself, for example one that is not yet published, build the image from the [Spring Authentication Server repository](https://github.com/swedenconnect/spring-authentication-server). This requires Java 21 or later and Maven:

```bash
cd spring-authentication-server
mvn clean install -DskipTests
cd sweden-connect-reference
mvn jib:dockerBuild@local
```

This builds the image `local/sweden-connect-reference-authn-server:<version>` into your local Docker, for example `local/sweden-connect-reference-authn-server:1.0.0-SNAPSHOT`. Jib builds it for `linux/amd64` unless told otherwise. On a machine with an ARM processor, such as a Mac with Apple silicon, add `-Djib.from.platforms=linux/arm64` to the last command, so that the image does not run under emulation.

Then set the image in `.env`:

```
REFERENCE_AUTHN_SERVER_IMAGE=local/sweden-connect-reference-authn-server:1.0.0-SNAPSHOT
```

and start the service again:

```bash
docker compose up -d reference-authn-server
```

To go back to the published image, remove the line from `.env`, or set it to the default from `.env.example`.

<a name="test-my-eid-build"></a>
## Using a local build of Test my eID

To run a version of Test my eID that you have built yourself, build the image from the [Test my eID repository](https://github.com/swedenconnect/test-my-eid). This requires Java 21 or later and Maven:

```bash
cd test-my-eid
mvn clean package -DskipTests
mvn jib:dockerBuild@local
```

This builds the image `local/test-my-eid:<version>` into your local Docker, for example `local/test-my-eid:4.0.0-SNAPSHOT`. As for the reference authentication server, add `-Djib.from.platforms=linux/arm64` to the last command on a machine with an ARM processor. Then set the image in `.env`:

```
TEST_MY_EID_IMAGE=local/test-my-eid:4.0.0-SNAPSHOT
```

and start the service again:

```bash
docker compose up -d test-my-eid
```

<a name="federation-image"></a>
## Using another image of the OpenID Federation service

The OpenID Federation service runs the published image `ghcr.io/swedenconnect/openid-federation-services:latest`. When you need a fix that is not yet released, use a snapshot or a build of your own, and set it in `.env`:

```
OPENID_FEDERATION_IMAGE=ghcr.io/swedenconnect/openid-federation-services:<version>
```

The configuration in [config/openid-federation](../config/openid-federation) needs version 1.0.0 or later.

To build the image yourself from the [OpenID Federation service repository](https://github.com/swedenconnect/openid-federation-services), with Java 25 and Maven:

```bash
cd openid-federation-services
mvn clean install -DskipTests
cd oidf-services
mvn compile jib:dockerBuild@local -Djib.from.platforms=linux/arm64
```

Use `linux/amd64` instead of `linux/arm64` on a machine with an Intel or AMD processor. This builds the image `local/oidf-services:latest` into your local Docker. Set it in `.env`:

```
OPENID_FEDERATION_IMAGE=local/oidf-services:latest
```

and start the service again:

```bash
docker compose up -d openid-federation
```

As for the reference authentication server, `docker compose pull` fails for a local image. Use `docker compose pull --ignore-pull-failures`.

<a name="adding-your-own-service"></a>
## Adding your own service

This section is about SAML. How to register a Relying Party or OpenID Provider in the OpenID Federation is described in [OpenID Federation in the Local Federation](openid-federation.md).

To test your own Service Provider against the reference authentication server, it must be part of the federation, and it must trust the federation:

1. Put the SAML metadata of your Service Provider in a file of its own in [config/metadata-aggregator/metadata](../config/metadata-aggregator/metadata), for example `my-sp.xml`. The aggregator reads the files again every minute and adds it to the feed.
2. Configure your Service Provider to read the Identity Provider metadata from https://local.fed.swedenconnect.se:11000/metadata/mdx/role/idp.xml, and to validate it with [config/common/metadata-signing.crt](../config/common/metadata-signing.crt). If it downloads the metadata over HTTPS, it must also trust [config/common/tls.crt](../config/common/tls.crt), for example through the trust store [config/common/trust.jks](../config/common/trust.jks) (password `secret`).
3. Send your authentication requests to the Identity Provider `https://local.fed.swedenconnect.se/idp`.

The reference authentication server downloads the metadata feed again within ten minutes. To make it pick up your Service Provider right away, use the `clients` endpoint of its Actuator, see [Audit entries and the Actuator](#audit-and-actuator).

An Identity Provider of your own is added in the same way, and its metadata then reaches Test my eID and the test client. They download the feed again within ten minutes, or at once when restarted with `docker compose restart test-my-eid test-client`.

<a name="regenerating-keys"></a>
## Regenerating keys and certificates

All keys, key stores and certificates are committed, so you never need to generate them to run the federation. If you want new ones, run [scripts/generate-credentials.sh](../scripts/generate-credentials.sh). It uses `keytool`, gives every key store and key the password `secret`, and replaces the existing files:

```bash
# Everything
scripts/generate-credentials.sh

# Only some of them
scripts/generate-credentials.sh tls metadata federation oidc reference test-my-eid test-client
```

| Target | Generates |
| :--- | :--- |
| `tls` | The TLS key store and certificate in `config/common`. |
| `metadata` | The metadata signing key of the aggregator, and its certificate in `config/common`. |
| `reference` | The SAML keys of the reference authentication server. |
| `test-my-eid` | The SAML keys of Test my eID. |
| `test-client` | The SAML keys of the test client. |
| `oidc` | The OpenID Connect signing keys of the reference authentication server and the test client. Test my eID uses its SAML keys for OpenID Connect. |
| `federation` | Every OpenID Federation key: the keys of the federation entities, the public keys of the trust anchor and the trust mark issuers in `config/common`, and the federation keys of the reference authentication server, Test my eID and the test client. The public keys of the three services are also written into the configuration of the federation service. |

The trust store, `config/common/trust.jks`, is rebuilt whenever the TLS or metadata signing certificate is replaced.

The metadata files of the aggregator hold the certificates of the SAML keys. After new SAML keys, restart the services and refresh the metadata:

```bash
docker compose up -d --force-recreate
scripts/refresh-metadata.sh
docker compose restart reference-authn-server test-my-eid test-client
```

After new OpenID Federation keys, restart the federation service, and give services that trust the federation the new trust anchor key:

```bash
docker compose restart openid-federation
```

The `federation` target creates `config/openid-federation/federation-keys.jks` anew, so keys that you have added to it yourself, such as the key of a [hosted Relying Party](openid-federation.md#adding-hosted-rp), must be added again.

After a new TLS certificate, accept it again in your browser, see [Accepting the TLS certificate](#accepting-the-tls-certificate).

<a name="refreshing-metadata"></a>
## Refreshing the metadata

The metadata aggregator builds its feed from the metadata files in [config/metadata-aggregator/metadata](../config/metadata-aggregator/metadata). The files of the services in this repository are committed. When the configuration or keys of one of these services change, its metadata changes too, and the committed file must be updated. [scripts/refresh-metadata.sh](../scripts/refresh-metadata.sh) fetches the metadata from the running services and updates the files:

```bash
# Every service
scripts/refresh-metadata.sh

# Only some of them
scripts/refresh-metadata.sh reference test-my-eid test-client
```

The script removes the signature, `validUntil` and `cacheDuration` of the fetched metadata, so that the committed files do not expire. The aggregator signs the feed and sets its validity.

The aggregator reads the files again within a minute. The services download the feed again within ten minutes, or at once when restarted:

```bash
docker compose restart reference-authn-server test-my-eid test-client
```

---

Copyright &copy; 2026, [Sweden Connect](https://www.swedenconnect.se). Licensed under version 2.0 of the [Apache License](http://www.apache.org/licenses/LICENSE-2.0).
