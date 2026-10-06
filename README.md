![Logo](https://raw.githubusercontent.com/swedenconnect/technical-framework/master/img/sweden-connect.png)

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

# Sweden Connect Local Federation

A Sweden Connect federation that runs on your own machine with Docker Compose. Use it to test your own Service Provider, Identity Provider, Relying Party or OpenID Provider against Sweden Connect services and test clients, without access to the Sweden Connect test federations.

For SAML, it runs a metadata aggregator that publishes the federation metadata, the [Sweden Connect reference authentication server](https://github.com/swedenconnect/spring-authentication-server/tree/main/sweden-connect-reference) as Identity Provider, [Test my eID](https://github.com/swedenconnect/test-my-eid) and the [Sweden Connect test client](https://github.com/swedenconnect/sweden-connect-test-client) as Service Providers, and Redis.

For OpenID Connect, it runs an OpenID Federation built like the Sweden Connect OpenID Federation, with a trust anchor, trust mark issuers and registration intermediates, hosted by the [OpenID Federation service](https://github.com/swedenconnect/openid-federation-services). The reference authentication server, Test my eID and the test client are registered in it. The reference authentication server is its OpenID Provider, and Test my eID and the test client are Relying Parties.

> All keys, key stores and certificates in this repository are test credentials. They are public and offer no protection. Never use them for anything but the local federation.

## Documentation

The [documentation](https://docs.swedenconnect.se/local-federation) describes how to set up and use the local federation.

---

Copyright &copy; 2026, [Sweden Connect](https://www.swedenconnect.se). Licensed under version 2.0 of the [Apache License](http://www.apache.org/licenses/LICENSE-2.0).
