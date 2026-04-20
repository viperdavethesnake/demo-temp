# Grafana renderer — tokens

Lab-only, committed plaintext. Regenerate if this leaves the lab.

## Renderer auth token (shared secret)
Baked into `renderer` container (`AUTH_TOKEN=`) and `grafana` container (`GF_RENDERING_RENDERER_TOKEN=`).

```
66ae4fb88d3a7ab1ecd055919acd589a7f1e7eef26d6cc1de82436e01c76bc1f
```

If either container is recreated, both must be recreated with the same value.

## Grafana service account (for issuing render requests)
- Name: `renderer` (service account id 2, login `sa-1-renderer`, role Admin)
- Token name: `tok1`

```
<redacted — GitHub push-protection blocked the literal glsa_* token>
Retrieve from the live box:  gh api (on sym02 only — token lives in grafana-data volume)
or regenerate via: curl -u admin:$GRAFANA_ADMIN_PASSWORD -H "Content-Type: application/json" \
  -X POST http://localhost:3000/api/serviceaccounts/2/tokens -d '{"name":"tok2"}'
```

Use as `Authorization: Bearer <token>` on requests to `http://localhost:3000/render/...`.

## Render examples

```bash
# Full dashboard PNG
curl -H "Authorization: Bearer <TOK>" \
  -o out.png \
  "http://localhost:3000/render/d/<uid>/<slug>?width=1600&height=900&timeout=60&from=now-24h&to=now"

# Single panel
curl -H "Authorization: Bearer <TOK>" \
  -o panel.png \
  "http://localhost:3000/render/d-solo/<uid>/<slug>?panelId=N&width=1000&height=500&from=now-24h&to=now"
```
