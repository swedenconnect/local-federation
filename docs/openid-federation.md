![Logo](https://raw.githubusercontent.com/swedenconnect/technical-framework/master/img/sweden-connect.png)

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

# OpenID Federation in the Local Federation

The local federation runs an OpenID Federation that is built like the Sweden Connect OpenID Federation. It has the same entities, roles, metadata policies and trust mark types, so that you can register your own Relying Parties and OpenID Providers, give them trust marks and test them against the Sweden Connect services before you move on to the Sandbox, QA or production federation.

All federation entities are hosted by one service, the [OpenID Federation service](https://github.com/swedenconnect/openid-federation-services), which reads the federation from JSON files in [config/openid-federation](../config/openid-federation). Registering an entity, or granting a trust mark, means editing a file and restarting the service. The service itself is described in [Services](services.md#openid-federation).

- [The federation structure](#structure)
  - [Entities and endpoints](#entities-and-endpoints)
  - [The trust anchor key](#trust-anchor-key)
  - [Sweden Connect environments](#environments)
- [The configuration files](#configuration-files)
- [Metadata policies](#metadata-policies)
- [The registered Sweden Connect services](#registered-services)
- [Adding a Relying Party that publishes its entity configuration](#adding-rp)
- [Adding a Relying Party hosted by the RP Registration Intermediate](#adding-hosted-rp)
- [Adding an OpenID Provider](#adding-op)
- [Granting, renewing and withdrawing trust marks](#trust-marks)
- [Setting up a service that joins the federation](#joining-service)
- [Checking a registration](#checking)

<a name="structure"></a>
## The federation structure

The structure follows [Sweden Connect - OpenID Federation Structure](https://docs.swedenconnect.se/federation/oidf-structure.html). Only the entity identifiers differ.

```
Trust Anchor (trustanchor), also the resolver
├── RP Registration Intermediate (im-reg-sc)          only openid_relying_party below it
│   ├── Sweden Connect test client (testrp1)
│   └── Test my eID
├── OP Registration Intermediate (im-reg-sc-op)       only openid_provider below it
│   └── Sweden Connect reference authentication server
├── Level of Assurance Trust Mark Issuer (tmi-loa)
└── Contracts Trust Mark Issuer (tmi-contracts)
```

- Trust Anchor – The root of the federation. Every participant trusts the federation through the trust anchor's key. The trust anchor also exposes the resolve endpoint, so it is the resolver of the federation, and resolve responses are signed with its key.
- RP Registration Intermediate – Registers Relying Parties. It issues the subordinate statements of the Relying Parties, and can host the entity configuration of a Relying Party that cannot publish one itself.
- OP Registration Intermediate – Registers OpenID Providers.
- Level of Assurance Trust Mark Issuer – Issues trust marks stating that an OpenID Provider is approved for a level of assurance.
- Contracts Trust Mark Issuer – Issues trust marks stating that a Relying Party or OpenID Provider has signed a Sweden Connect contract.

The trust anchor's subordinate statements for the two intermediates carry the federation-wide metadata policy, see [Metadata policies](#metadata-policies), and constrain the entity types below them: only `openid_relying_party` below `im-reg-sc` and only `openid_provider` below `im-reg-sc-op`.

The trust mark issuers are subordinates of the trust anchor, so that their keys can be validated through a trust chain. In the Sandbox federation they are placed below the intermediates instead, which makes no difference to how their trust marks are validated.

Each federation entity has its own federation key, an EC P-521 key, and signs with ES512.

<a name="entities-and-endpoints"></a>
### Entities and endpoints

All entities are reached on port `11040`. The entity configuration of each entity is published at `<entity identifier>/.well-known/openid-federation`.

**Trust Anchor**

- Entity identifier: `https://local.fed.swedenconnect.se:11040/trustanchor`
- Fetch endpoint: `https://local.fed.swedenconnect.se:11040/trustanchor/fetch`
- Subordinate listing endpoint: `https://local.fed.swedenconnect.se:11040/trustanchor/subordinate_listing`
- Resolve endpoint: `https://local.fed.swedenconnect.se:11040/trustanchor/resolve`
- Discovery endpoint: `https://local.fed.swedenconnect.se:11040/trustanchor/discovery`

**Level of Assurance Trust Mark Issuer**

- Entity identifier: `https://local.fed.swedenconnect.se:11040/tmi-loa`
- Trust mark endpoint (for issuance): `https://local.fed.swedenconnect.se:11040/tmi-loa/trust_mark`
- Trust mark status endpoint: `https://local.fed.swedenconnect.se:11040/tmi-loa/trust_mark_status`
- Trust mark listing endpoint: `https://local.fed.swedenconnect.se:11040/tmi-loa/trust_mark_listing`

**Contracts Trust Mark Issuer**

- Entity identifier: `https://local.fed.swedenconnect.se:11040/tmi-contracts`
- Trust mark endpoint (for issuance): `https://local.fed.swedenconnect.se:11040/tmi-contracts/trust_mark`
- Trust mark status endpoint: `https://local.fed.swedenconnect.se:11040/tmi-contracts/trust_mark_status`
- Trust mark listing endpoint: `https://local.fed.swedenconnect.se:11040/tmi-contracts/trust_mark_listing`

**RP Registration Intermediate**

- Entity identifier: `https://local.fed.swedenconnect.se:11040/im-reg-sc`
- Fetch endpoint: `https://local.fed.swedenconnect.se:11040/im-reg-sc/fetch`
- Subordinate listing endpoint: `https://local.fed.swedenconnect.se:11040/im-reg-sc/subordinate_listing`

**OP Registration Intermediate**

- Entity identifier: `https://local.fed.swedenconnect.se:11040/im-reg-sc-op`
- Fetch endpoint: `https://local.fed.swedenconnect.se:11040/im-reg-sc-op/fetch`
- Subordinate listing endpoint: `https://local.fed.swedenconnect.se:11040/im-reg-sc-op/subordinate_listing`

**Trust mark types**

| Trust mark type | Issuer | Granted to |
| :--- | :--- | :--- |
| `https://id.swedenconnect.se/loa/loa2` | `tmi-loa` | The reference OP |
| `https://id.swedenconnect.se/loa/loa3` | `tmi-loa` | The reference OP |
| `https://id.swedenconnect.se/loa/loa4` | `tmi-loa` | The reference OP |
| `https://id.swedenconnect.se/loa/eidas` | `tmi-loa` | No one |
| `https://id.swedenconnect.se/loa/nonresident` | `tmi-loa` | No one |
| `https://id.swedenconnect.se/contract/sc/eid-authorization-system` | `tmi-contracts` | The reference OP, the test client and Test my eID |
| `https://id.swedenconnect.se/contract/sc/prepaid-auth-2021` | `tmi-contracts` | The reference OP |

The meaning of each type is given in Section 4 of the [structure document](https://docs.swedenconnect.se/federation/oidf-structure.html#name-trust-marks). Issued trust marks are valid for one year.

<a name="trust-anchor-key"></a>
### The trust anchor key

The federation key of the trust anchor is published in [config/common](../config/common), in the same three forms that the structure document uses:

- [oidf-trust-anchor.pem](../config/common/oidf-trust-anchor.pem) – The public key, PEM encoded.
- [oidf-trust-anchor.jwk](../config/common/oidf-trust-anchor.jwk) – The public key as a JWK. Its `kid` is the one the trust anchor uses.
- [oidf-trust-anchor.jwks](../config/common/oidf-trust-anchor.jwks) – The same JWK in a JWK set, for services that want a JWK set.

The keys of the two trust mark issuers are published as JWK sets next to it, [oidf-tmi-loa.jwks](../config/common/oidf-tmi-loa.jwks) and [oidf-tmi-contracts.jwks](../config/common/oidf-tmi-contracts.jwks), for services that verify their own trust marks with configured issuer keys.
- [oidf-trust-anchor.crt](../config/common/oidf-trust-anchor.crt) – A self-signed certificate holding the public key. Only the key in the certificate is of interest, do not configure trust in the certificate itself.

Configure this key in your service as the key of the trust anchor. Do not take the key from the trust anchor's own entity configuration, since that offers no protection against a rogue trust anchor.

> This is a test key. Its private key is committed to this repository, so it offers no protection at all.

<a name="environments"></a>
### Sweden Connect environments

The same entity names are used in every Sweden Connect environment. Only the base URL differs.

| Environment | Base URL of the entity identifiers | Trust anchor key |
| :--- | :--- | :--- |
| Local federation | `https://local.fed.swedenconnect.se:11040` | [config/common](../config/common) |
| Sandbox | `https://fed.sandbox.swedenconnect.se` | [Section 5.3.1](https://docs.swedenconnect.se/federation/oidf-structure.html#name-trust-anchor-3) of the structure document |
| QA | `https://qa.fed.swedenconnect.se` | [Section 5.2.1](https://docs.swedenconnect.se/federation/oidf-structure.html#name-trust-anchor-2) of the structure document |
| Production | `https://fed.swedenconnect.se` | [Section 5.1.1](https://docs.swedenconnect.se/federation/oidf-structure.html#name-trust-anchor) of the structure document |

For example, the trust anchor is `https://local.fed.swedenconnect.se:11040/trustanchor` here and `https://fed.sandbox.swedenconnect.se/trustanchor` in the Sandbox. A service that is set up against the local federation is moved to another environment by changing the base URL and the trust anchor key, and by registering it there, see [Joining the Federation](https://docs.swedenconnect.se/federation/oidf-structure.html#name-joining-the-federation).

<a name="configuration-files"></a>
## The configuration files

The federation is read from these files in [config/openid-federation](../config/openid-federation) when the service starts. After a change, restart the service:

```bash
docker compose restart openid-federation
```

| File | Contents |
| :--- | :--- |
| [entities.json](../config/openid-federation/entities.json) | The entities that the service hosts: the federation entities and any hosted Relying Parties. Each entry gives the entity identifier, the key it signs with, its authority hints and the metadata of its entity configuration. |
| [trust-anchors.json](../config/openid-federation/trust-anchors.json) | The trust anchor and the intermediates, each with its subordinates. A subordinate entry is the content of the subordinate statement: the subordinate's federation keys, `metadata`, metadata policy and constraints. |
| [trust-mark-issuers.json](../config/openid-federation/trust-mark-issuers.json) | The two trust mark issuers, their trust mark types and the subjects that hold each type. |
| [resolvers.json](../config/openid-federation/resolvers.json) | The resolver, which is the trust anchor itself. |
| [application-compose.yml](../config/openid-federation/application-compose.yml) | The service settings, the federation keys of the federation entities, and the public federation keys of the services that publish their own entity configurations. |
| `federation-keys.jks` | The federation keys of the federation entities, one alias per entity, password `secret`. |

Keys are referenced from the JSON files by name. `federation:<name>` is a key of a federation entity, `hosted:<name>` a key that signs a hosted entity configuration, and `public:<name>` the public key of an entity that publishes its own entity configuration. A misspelled reference in `trust-anchors.json` stops the service from starting, with the reason "No value present", and in `entities.json` it leaves the entity out with a warning that the reference "contained no valid keys". Check the state and the log after a change:

```bash
docker compose ps openid-federation
docker compose logs openid-federation | grep -iE "warn|error|reason"
```

The JSON files do not allow comments. The format of every setting is described in [Service Configuration](https://github.com/swedenconnect/openid-federation-services/blob/main/docs/service-configuration.md) and [Demo Mode Configuration](https://github.com/swedenconnect/openid-federation-services/blob/main/docs/service-configuration-demo.md) of the service.

<a name="metadata-policies"></a>
## Metadata policies

The metadata policies are those of Section 6 of [Sweden Connect - OpenID Connect Metadata Requirements](https://docs.swedenconnect.se/federation/oidc-metadata-requirements.html#name-sweden-connect-metadata-pol).

**The trust anchor policy.** The subordinate statements that the trust anchor issues for `im-reg-sc` and `im-reg-sc-op` carry the policy of Section 6.1, so it applies to every Relying Party and OpenID Provider. It is given in full in both subordinate entries of the trust anchor in `trust-anchors.json`.

**The values set by the intermediates.** The subordinate statement that an intermediate issues for an entity carries the values of Section 6.2:

- `organization_name` and `organization_identifier` in the `metadata` claim. `organization_name` is given in Swedish (`#sv`), English (`#en`) and without a language tag, where the untagged value is the legal name of the organization.
- `display_name` and `logo_uri` pinned with the `value` operator in the `metadata_policy` claim, and for a Relying Party also `client_name`, and for an OpenID Provider also `acr_values_supported`.
- `display_name` and `client_name` are pinned in Swedish, English and without a language tag. The untagged value is the Swedish one, since Swedish is the default language of the federation.
- A Relying Party that does not declare `display_name` gets the value of its `client_name`.

**Left out.** Section 6.1 removes `id_token_signed_response_alg` and `userinfo_signed_response_alg` from Relying Party metadata using the `value` operator with a `null` value. The service puts these operators in the subordinate statements, but every resolve of a Relying Party then fails with an internal error. They are therefore left out, and a Relying Party that declares these parameters keeps them in its resolved metadata. Everything else in Section 6 is in place.

<a name="registered-services"></a>
## The registered Sweden Connect services

The three Sweden Connect services of the local federation are registered, each with a federation key of its own, an EC P-256 key generated by [scripts/generate-credentials.sh](../scripts/generate-credentials.sh):

| Service | Entity identifier | Registered under | Federation key |
| :--- | :--- | :--- | :--- |
| Sweden Connect reference authentication server (OP) | `https://local.fed.swedenconnect.se:11010` | `im-reg-sc-op` | `config/reference-authn-server/federation-key.jks` |
| Test my eID (RP) | `https://local.fed.swedenconnect.se:11020/testmyeid` | `im-reg-sc` | `config/test-my-eid/federation-key.jks` |
| Sweden Connect test client, Test RP 1 (RP) | `https://local.fed.swedenconnect.se:11030/testrp1` | `im-reg-sc` | `config/test-client/federation-key.jks` |

Each key store has one key, alias `federation`, password `secret`. Its certificate is next to it as `federation-key.crt`.

The entity identifier of the OpenID Provider is its issuer, which is the base URL of the reference authentication server. The test client forms the identifier of a Relying Party from its base URL and the RP's path suffix, and Test my eID from its base URL and context path.

The services publish their own entity configurations, signed with these keys, and fetch their trust marks from the issuers: the reference OpenID Provider `loa2`, `loa3`, `loa4` and both contract trust marks, and the two Relying Parties `eid-authorization-system`. All three are resolved at the trust anchor. The reference OpenID Provider resolves its clients at the trust anchor too, so every Relying Party registered under `im-reg-sc` can use it.

The reference OpenID Provider and Test my eID publish their trust marks in the form of OpenID Federation 1.0, with `trust_mark_type` only. The federation service reads only trust marks that also carry the older `id` member, so the resolve responses for these two hold no trust marks. The test client publishes both members, and its trust mark is in its resolve response. A Relying Party that checks the level of assurance trust marks of the OpenID Provider in its resolve response, as Test my eID does, therefore does not find them.

The Section 6.2 values are taken from the configuration of each service: the display names, client names and logotypes that it publishes, and its organization, Sweden Connect with organization number `2021006883`. The OpenID Provider's `acr_values_supported` is pinned to the level of assurance URIs that it declares for LoA 2, 3 and 4, `http://id.elegnamnden.se/loa/1.0/loa2`, `http://id.elegnamnden.se/loa/1.0/loa3` and `http://id.elegnamnden.se/loa/1.0/loa4`.

<a name="adding-rp"></a>
## Adding a Relying Party that publishes its entity configuration

A Relying Party that publishes its own entity configuration at `<entity identifier>/.well-known/openid-federation` is registered under the RP Registration Intermediate. The example registers `https://rp.example.com`.

1. **The federation key.** The Relying Party signs its entity configuration with a federation key of its own, for example an EC P-256 key. Use a key type and size that [Sweden Connect - Security Requirements](https://docs.swedenconnect.se/federation/security-requirements.html) allows. Add the public key to `federation.keys.additional-keys` in [application-compose.yml](../config/openid-federation/application-compose.yml), outside the generated BEGIN and END blocks, either as a PEM certificate or public key, or as a base64-encoded JWK:

   ```yaml
   federation:
     keys:
       additional-keys:
         # ...
         - name: example-rp
           certificate: |
             -----BEGIN CERTIFICATE-----
             MIIB...
             -----END CERTIFICATE-----
         # or, instead of the certificate:
         #  base64-encoded-public-jwk: eyJrdHkiOiJFQyIs...
   ```

   The `kid` of the key is its JWK thumbprint (RFC 7638). The `kid` in the header of the Relying Party's entity configuration must be the same.

2. **The subordinate entry.** Add the Relying Party to the subordinates of `https://local.fed.swedenconnect.se:11040/im-reg-sc` in [trust-anchors.json](../config/openid-federation/trust-anchors.json), with the key, the organization in `metadata` and the Section 6.2 values in `policy`:

   ```json
   {
     "entity-identifier": "https://rp.example.com",
     "jwks": "public:example-rp",
     "metadata": {
       "openid_relying_party": {
         "organization_name#sv": "Exempel AB",
         "organization_name#en": "Example Ltd",
         "organization_name": "Exempel AB",
         "organization_identifier": "urn:glue:iso6523:0007:5560000000"
       }
     },
     "policy": {
       "id": "example-rp",
       "policy": {
         "openid_relying_party": {
           "display_name#sv": { "value": "Min tjänst" },
           "display_name#en": { "value": "My service" },
           "display_name": { "value": "Min tjänst" },
           "client_name#sv": { "value": "Min tjänst" },
           "client_name#en": { "value": "My service" },
           "client_name": { "value": "Min tjänst" },
           "logo_uri": { "value": "https://rp.example.com/logo.svg" }
         }
       }
     }
   }
   ```

   `policy.id` is a free name of your choice, and `policy.policy` becomes the `metadata_policy` claim. Take the values from what the Relying Party publishes: its `client_name` in Swedish and English, `display_name` if it declares one (otherwise the same as `client_name`), and `logo_uri`. The organization identifier holds the ten-digit organization number, see Section 3 of the [metadata requirements](https://docs.swedenconnect.se/federation/oidc-metadata-requirements.html#name-common-requirements).

3. **The Relying Party itself.** Its entity configuration must hold `https://local.fed.swedenconnect.se:11040/im-reg-sc` in `authority_hints`, see [Setting up a service that joins the federation](#joining-service).

4. **Restart** the federation service: `docker compose restart openid-federation`.

The Relying Party is now listed by `im-reg-sc`, and its subordinate statement can be fetched. The resolver reads the entity configurations of the subordinates when it starts, and again every ten minutes. If the Relying Party was not running when the federation service started, resolving it succeeds within ten minutes, or at once after another restart.

<a name="adding-hosted-rp"></a>
## Adding a Relying Party hosted by the RP Registration Intermediate

A Relying Party that cannot publish an entity configuration of its own can have it hosted by the RP Registration Intermediate, according to [OpenID Federation Entity Configuration Hosting 1.0](https://www.oidc.se/openid-federation-hosting/main.html). The intermediate then serves the entity configuration at a URL of its own, and its subordinate statement for the Relying Party holds that URL in the `ec_location` claim. A resolver that builds the trust chain from the trust anchor downwards, as the trust anchor's resolver does, finds the entity configuration there.

In this service the hosted entity configuration is built from `entities.json` and signed with a key that the federation service holds, so the Relying Party itself needs no federation key. The example hosts `https://rp.example.com` at `https://local.fed.swedenconnect.se:11040/im-reg-sc/hosted/example-rp`.

1. **A hosting key.** Generate a key for the hosted entity configuration in `federation-keys.jks`:

   ```bash
   keytool -genkeypair -keystore config/openid-federation/federation-keys.jks -storetype JKS \
     -storepass secret -keypass secret -alias example-rp -keyalg EC -groupname secp256r1 \
     -sigalg SHA256withECDSA -validity 3650 -dname "CN=Example RP, OU=TEST ONLY"
   ```

   and make it known in [application-compose.yml](../config/openid-federation/application-compose.yml), as a credential bundle mapped for hosted use:

   ```yaml
   credential:
     bundles:
       jks:
         # ...
         example-rp:
           name: "Example RP"
           store-reference: federation-keys
           key:
             alias: example-rp
             key-password: secret

   federation:
     keys:
       mapping:
         federation:
           # ...
         hosted:
           - example-rp
   ```

   Note that `scripts/generate-credentials.sh federation` recreates `federation-keys.jks` and removes such keys.

2. **The hosted entity configuration.** Add the Relying Party to [entities.json](../config/openid-federation/entities.json). `virtual-entity-id` is the URL it is hosted at, and the entity configuration is served at `<virtual-entity-id>/.well-known/openid-federation`. `metadata` holds the Relying Party's metadata, including its OpenID Connect keys in `jwks` or `jwks_uri`, and must meet the [metadata requirements](https://docs.swedenconnect.se/federation/oidc-metadata-requirements.html):

   ```json
   {
     "entity-identifier": "https://rp.example.com",
     "virtual-entity-id": "https://local.fed.swedenconnect.se:11040/im-reg-sc/hosted/example-rp",
     "jwks": "hosted:example-rp",
     "authority-hints": [ "https://local.fed.swedenconnect.se:11040/im-reg-sc" ],
     "metadata": {
       "openid_relying_party": {
         "redirect_uris": [ "https://rp.example.com/callback" ],
         "response_types": [ "code" ],
         "grant_types": [ "authorization_code" ],
         "token_endpoint_auth_method": "private_key_jwt",
         "client_uri": "https://rp.example.com",
         "contacts": [ "operations@example.com" ],
         "logo_uri": "https://rp.example.com/logo.svg",
         "client_name#sv": "Min tjänst",
         "client_name#en": "My service",
         "jwks_uri": "https://rp.example.com/jwks"
       }
     }
   }
   ```

3. **The subordinate entry.** Add the Relying Party to the subordinates of `im-reg-sc` in [trust-anchors.json](../config/openid-federation/trust-anchors.json) as in [the previous section](#adding-rp), with the same `virtual-entity-id` and the hosting key:

   ```json
   {
     "entity-identifier": "https://rp.example.com",
     "virtual-entity-id": "https://local.fed.swedenconnect.se:11040/im-reg-sc/hosted/example-rp",
     "jwks": "hosted:example-rp",
     "metadata": { "openid_relying_party": { "organization_name": "Exempel AB", "...": "..." } },
     "policy": { "id": "example-rp", "policy": { "openid_relying_party": { "...": "..." } } }
   }
   ```

   Because the hosting URL differs from the entity identifier, the subordinate statement gets the claim `"ec_location": "https://local.fed.swedenconnect.se:11040/im-reg-sc/hosted/example-rp/.well-known/openid-federation"`. You can also set `ec-location` yourself, as an absolute URL or as a path that is appended to the `virtual-entity-id`.

4. **Restart** the federation service: `docker compose restart openid-federation`.

The hosting specification requires that an intermediate checks that the party asking for hosting has the right to the domain of the entity identifier, and that the identifier is not used by another entity of the federation. In the local federation you are that party, so make sure the identifier is not registered elsewhere in the federation.

<a name="adding-op"></a>
## Adding an OpenID Provider

An OpenID Provider is registered under the OP Registration Intermediate, and must publish its own entity configuration. The reference authentication server is registered this way: look at its entry under `im-reg-sc-op` in [trust-anchors.json](../config/openid-federation/trust-anchors.json), its key `reference-authn-server` in [application-compose.yml](../config/openid-federation/application-compose.yml), and the `authn-server.oidc.federation` settings in its own [application-compose.yml](../config/reference-authn-server/application-compose.yml). The steps are those of [Adding a Relying Party that publishes its entity configuration](#adding-rp), with these differences:

- The subordinate entry goes under `https://local.fed.swedenconnect.se:11040/im-reg-sc-op` in [trust-anchors.json](../config/openid-federation/trust-anchors.json).
- The entity type in `metadata` and `policy` is `openid_provider`.
- The policy pins `display_name` and `logo_uri`, but not `client_name`.
- The policy pins `acr_values_supported` to the authentication context URIs that the OpenID Provider is approved for, see Section 3.1.1 of [Registry for identifiers](https://docs.swedenconnect.se/technical-framework/latest/03_-_Registry_for_Identifiers.html). The pinned list replaces what the OpenID Provider declares, so an RP never sees a value the OpenID Provider has not been approved for.
- The entity configuration of the OpenID Provider holds `https://local.fed.swedenconnect.se:11040/im-reg-sc-op` in `authority_hints`.

```json
{
  "entity-identifier": "https://op.example.com",
  "jwks": "public:example-op",
  "metadata": {
    "openid_provider": {
      "organization_name#sv": "Exempel AB",
      "organization_name#en": "Example Ltd",
      "organization_name": "Exempel AB",
      "organization_identifier": "urn:glue:iso6523:0007:5560000000"
    }
  },
  "policy": {
    "id": "example-op",
    "policy": {
      "openid_provider": {
        "display_name#sv": { "value": "Exempel-OP" },
        "display_name#en": { "value": "Example OP" },
        "display_name": { "value": "Exempel-OP" },
        "logo_uri": { "value": "https://op.example.com/logo.svg" },
        "acr_values_supported": {
          "value": [ "http://id.elegnamnden.se/loa/1.0/loa3", "http://id.elegnamnden.se/loa/1.0/loa2" ]
        }
      }
    }
  }
}
```

Grant the OpenID Provider the matching level of assurance trust marks and the contract trust marks it delivers under, see the next section.

<a name="trust-marks"></a>
## Granting, renewing and withdrawing trust marks

The trust marks are configured in [trust-mark-issuers.json](../config/openid-federation/trust-mark-issuers.json). Each trust mark type of an issuer has a list of subjects, the entities that hold it. An issuer issues a trust mark on request, to a subject in the list, and refuses (HTTP 404) anyone else. Restart the service after a change: `docker compose restart openid-federation`.

**Granting.** Add the entity identifier to the subjects of the trust mark type, at the issuer that issues it:

```json
{
  "trust-mark-type": "https://id.swedenconnect.se/contract/sc/eid-authorization-system",
  "trust-mark-subjects": [
    { "sub": "https://local.fed.swedenconnect.se:11010", "granted": "2026-10-01T00:00:00Z" },
    { "sub": "https://rp.example.com", "granted": "2026-10-03T00:00:00Z" }
  ]
}
```

`granted` is when the trust mark was granted, in UTC. The entity fetches the trust mark from the issuer's trust mark endpoint and publishes it in the `trust_marks` claim of its entity configuration, see [Setting up a service that joins the federation](#joining-service). For a hosted Relying Party, add a `trust-mark-source` to its entry in `entities.json`, so that the federation service fetches the trust mark and puts it in the hosted entity configuration: `"trust-mark-source": [ { "issuer": "https://local.fed.swedenconnect.se:11040/tmi-contracts", "trust-mark-type": "https://id.swedenconnect.se/contract/sc/eid-authorization-system" } ]`.

**Renewing.** Every issued trust mark is valid for one year from when it was issued, set by `trust-mark-validity-duration` (`P365D`). The holder renews it by fetching a new one from the trust mark endpoint before the old one expires, which a service normally does by itself. A grant can be limited in time with `expires`, for example `"expires": "2027-06-30T00:00:00Z"`. No trust mark then lives past that time. To renew such a grant, move `expires` forward.

**Withdrawing.** Remove the subject from the list. The issuer then refuses to issue the trust mark. Trust marks that were issued earlier stay valid until they expire, and the trust mark status endpoint reports them as `active` as long as their signature is valid.

The service also supports `"revoked": true` on a subject, and `expires` in the past. They only change what the trust mark status endpoint reports, `revoked` or `expired`. The issuer keeps issuing trust marks to such a subject, so remove the subject to withdraw a trust mark.

<a name="joining-service"></a>
## Setting up a service that joins the federation

What the metadata of your Relying Party or OpenID Provider must contain is given by [Sweden Connect - OpenID Connect Metadata Requirements](https://docs.swedenconnect.se/federation/oidc-metadata-requirements.html). Besides its metadata, the service needs the following settings for the local federation.

| Setting | Value |
| :--- | :--- |
| Trust anchor | Entity identifier `https://local.fed.swedenconnect.se:11040/trustanchor`, with the key in [config/common](../config/common), see [The trust anchor key](#trust-anchor-key). |
| Authority hints | `https://local.fed.swedenconnect.se:11040/im-reg-sc` for a Relying Party, `https://local.fed.swedenconnect.se:11040/im-reg-sc-op` for an OpenID Provider. |
| Resolve endpoint | `https://local.fed.swedenconnect.se:11040/trustanchor/resolve`. Resolve responses are signed with the trust anchor key. |
| Trust mark issuers | `https://local.fed.swedenconnect.se:11040/tmi-loa` for level of assurance trust marks, and `https://local.fed.swedenconnect.se:11040/tmi-contracts` for contract trust marks. Their keys are in `config/common/oidf-tmi-loa.jwks` and `config/common/oidf-tmi-contracts.jwks`. A trust mark is fetched with `GET <trust mark endpoint>?trust_mark_type=<type>&sub=<entity identifier>`, see [Entities and endpoints](#entities-and-endpoints). |
| Finding OpenID Providers | The subordinate listing of the OP Registration Intermediate, `https://local.fed.swedenconnect.se:11040/im-reg-sc-op/subordinate_listing`. Resolve each listed entity at the resolve endpoint to get its metadata. |
| Finding Relying Parties | The subordinate listing of the RP Registration Intermediate, `https://local.fed.swedenconnect.se:11040/im-reg-sc/subordinate_listing`. |
| Federation key | A key of the service's own, whose public key you add to the federation, see [Adding a Relying Party that publishes its entity configuration](#adding-rp). |
| TLS | All endpoints use the self-signed certificate [config/common/tls.crt](../config/common/tls.crt), which the service must trust. A Java service can use the trust store [config/common/trust.jks](../config/common/trust.jks) (password `secret`). |

A service that runs in a container must reach `local.fed.swedenconnect.se` on your machine, for example with `extra_hosts: ["local.fed.swedenconnect.se:host-gateway"]` in Docker Compose. A service that runs directly on your machine uses the hosts file entry, see [Setting up the local federation](setup.md#prerequisites). The federation service in turn must reach the entity configuration of your service, so publish it on a URL that resolves from inside a container, which `localhost` does not.

<a name="checking"></a>
## Checking a registration

The federation answers with signed JWTs. This shell function prints the payload of a JWT as JSON. It needs `base64` and [jq](https://jqlang.org/), and works in `bash` and `zsh`:

```bash
jwt_payload() {
  local p
  p="$(cut -d. -f2 | tr '_-' '/+')"
  while [ $(( ${#p} % 4 )) -ne 0 ]; do p="${p}="; done
  printf '%s' "${p}" | base64 -d | jq .
}
```

The examples are run from the root of the repository, and use the test RP of the test client. Replace it with the entity identifier of your own entity.

```bash
FED=https://local.fed.swedenconnect.se:11040
RP=https://local.fed.swedenconnect.se:11030/testrp1

# The entity configuration of an entity hosted by the federation, here the trust anchor
curl -s --cacert config/common/tls.crt $FED/trustanchor/.well-known/openid-federation | jwt_payload

# The entity configuration that the entity publishes itself
curl -s --cacert config/common/tls.crt $RP/.well-known/openid-federation | jwt_payload

# The listing of the intermediate, which should hold the entity
curl -s --cacert config/common/tls.crt $FED/im-reg-sc/subordinate_listing | jq .

# The subordinate statement, with the federation key, metadata and metadata policy
curl -s --cacert config/common/tls.crt "$FED/im-reg-sc/fetch?sub=$RP" | jwt_payload

# The resolved metadata and trust chain
curl -s --cacert config/common/tls.crt "$FED/trustanchor/resolve?sub=$RP&trust_anchor=$FED/trustanchor" | jwt_payload

# A trust mark
curl -s --cacert config/common/tls.crt \
  "$FED/tmi-contracts/trust_mark?trust_mark_type=https://id.swedenconnect.se/contract/sc/eid-authorization-system&sub=$RP" \
  | jwt_payload
```

When something is wrong, the federation answers with a JSON error instead of a JWT. A few hints:

- A resolve that fails with "Resolver found no subject" means that the resolver could not read the entity configuration of the entity. Check that the entity publishes it, that it is signed with the key in the subordinate entry, and that it was reachable when the resolver last read it. The resolver reads again every ten minutes, or at once when the federation service is restarted.
- The log of the federation service shows the errors of the trust chain building: `docker compose logs openid-federation`.

---

Copyright &copy; 2026, [Sweden Connect](https://www.swedenconnect.se). Licensed under version 2.0 of the [Apache License](http://www.apache.org/licenses/LICENSE-2.0).
