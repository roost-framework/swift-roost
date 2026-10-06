# ``RoostTest``

Test Roost applications in-process, with the same middleware and response lifecycle.

## Overview

Create a ``TestApp`` to send requests without opening a server port.
Use a ``TestBrowser`` when a workflow needs cookies across requests, and inspect
the returned ``TestResponse`` for status, headers, text, or decoded JSON.

Database tests can inject a transaction-owned repository through
``withTestRollback(repository:_:)``. The harness also exposes application
services and in-process channel and SSE helpers.

> Important: These helpers document the Roost development API. They do not
> establish that an external transport, storage adapter, or deployment works.

## Topics

### Test an application

- <doc:TestingHTTP>
- <doc:BrowserWorkflows>
- <doc:DatabaseIsolation>

### Requests and responses

- ``TestApp``
- ``TestBrowser``
- ``TestResponse``

### Database isolation

- ``withTestRollback(repository:_:)``

### In-process channels and presence

- ``TestChannelSocket``
- ``ChannelReply``
- ``PresenceAccessor``
