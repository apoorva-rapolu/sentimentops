# tests/smoke/ — post-deploy smoke tests

**Owner:** Manik. Black-box tests for the *deployed* API (contract sections 2 and 7). They use HTTP only and never import `app/`.

```bash
pip install -r tests/smoke/requirements.txt
API_BASE_URL="<terraform output api_base_url>" pytest -v tests/smoke
```

- Against the local dev server: `python app/dev_server.py` in one terminal, then `API_BASE_URL=http://localhost:8000 pytest -v tests/smoke`.
- Optional `SMOKE_MAX_LATENCY_S` (default 10) sets the round-trip limit for one prediction.
- Run automatically by `.github/workflows/deploy.yml` after the Step Functions deployment succeeds. The state machine runs its own, smaller smoke check (health, predict, bad input) by invoking the Lambda directly, because pytest cannot run inside Step Functions.
