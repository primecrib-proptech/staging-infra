# WebSocket to core – diagnostics

Core shows **0 WebSocket sessions**, so the upgrade request is not reaching the core. Use these steps to see where it stops.

## 1. Confirm Traefik sends `/api/v1/live` to the core

From a machine that can reach staging:

```bash
# Should hit the CORE (ticket endpoint). If 401 = core reached, wrong auth. If 200 = core reached, ticket returned.
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "x-api-key: YOUR_API_KEY" \
  "https://staging.api.primecrib.app/api/v1/live/ticket"
```

- **200** → Traefik is routing `Host(staging.api.primecrib.app) && PathPrefix(/api/v1/live)` to the core. So routing is correct; the problem is specific to the WebSocket upgrade.
- **502/503** → Traefik cannot reach the core (check service name `proptech_api:8081` and network).
- **401 from gateway** → Request is still going to the **gateway** (router not applied or wrong priority). Reload Traefik and ensure `proptech-live-websocket` has `priority: 10` and `proptech-gateway-service` has `priority: 1`.

## 2. Trigger a WebSocket upgrade and inspect response

```bash
curl -i -N \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  "https://staging.api.primecrib.app/api/v1/live/ws?ticket=any-uuid-here"
```

- **101 Switching Protocols** → Upgrade reached the core and succeeded; problem may be ticket validation or browser/client.
- **404** → Path not found (wrong path or not routed to core).
- **502 Bad Gateway** → Traefik could not connect to the core backend.
- **Connection closed with no response** → Connection dropped before 101 (proxy/timeout/firewall).

## 3. Traefik

- Reload dynamic config so `proptech-live-websocket` (service = `proptech-core-service`) is loaded.
- In Traefik dashboard or access log, confirm that requests to `https://staging.api.primecrib.app/api/v1/live/ws` are handled by router `proptech-live-websocket`, not `proptech-gateway-service`.
- Confirm backend `proptech-core-service` → `http://proptech_api:8081` and that Traefik can resolve and reach `proptech_api` on the same Docker network.

## 4. Core

- Ensure the app is bound to `0.0.0.0` (or equivalent) so it accepts connections from Traefik.
- After a WebSocket attempt, check logs for any handshake or WebSocket errors.
- If 1 and 2 show the core is reached and returns 101, check ticket validation (Redis, `WebSocketTicketService.consumeTicket`).
