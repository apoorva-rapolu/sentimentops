# frontend/ — demo page

**Owner:** Apoorva. Plain HTML/CSS/JS, no build step. Hosted on the S3 frontend bucket.

| File | What it does |
| --- | --- |
| `index.html` | Page layout |
| `style.css` | Styles (light + dark mode, works on phones) |
| `app.js` | Calls `GET /health` and `POST /predict`, shows the result and a session history |
| `config.js` | `API_BASE_URL` — empty = mock mode |

## Run locally

```bash
cd frontend
python -m http.server 8080     # open http://localhost:8080
```

- **Mock mode** (default): `API_BASE_URL` is empty, answers are faked in the browser. No backend needed.
- **Against the local API:** run `python app/dev_server.py`, set `API_BASE_URL: "http://localhost:8000"`.
- **Against AWS:** set `API_BASE_URL` to the Terraform output `api_base_url`.

## For Manik's deploy workflow

Before syncing to S3, overwrite `config.js` with the real URL, e.g.

```bash
echo "window.SENTIMENTOPS_CONFIG = { API_BASE_URL: \"$API_BASE_URL\" };" > frontend/config.js
aws s3 sync frontend/ s3://$FRONTEND_BUCKET --exclude README.md --delete
```
