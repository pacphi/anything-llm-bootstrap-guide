# AnythingLLM Docker Stack

This project runs AnythingLLM with PostgreSQL + pgvector behind Caddy, and supports both local HTTPS and public-domain HTTPS.

It is designed for macOS and Linux, keeps credentials out of the Compose file, and stores data on the host filesystem.

AnythingLLM's Docker docs note that service-to-service connections inside containers cannot use `localhost`, `127.0.0.1`, or `0.0.0.0`, so the database host in this stack is always `postgres`.

## Requirements

- Docker
- Docker Compose
- Bash
- OpenSSL
- sudo
- A public domain only if you want public HTTPS

## Setup

Run:

```bash
./scripts/setup.sh
```

The script validates dependencies first, then:

- detects macOS or Linux,
- proposes OS-aware default storage paths,
- lets you confirm or override those paths,
- creates `.env`,
- generates `secrets/postgres_password.txt`,
- optionally adds `anythingllm.localhost` to `/etc/hosts`,
- optionally renders `Caddyfile.public` from `Caddyfile.public.tmpl` if you enter a domain.

## Directory layout

```text
anythingllm-stack/
├── compose.yml
├── .env
├── Caddyfile.local
├── Caddyfile.public.tmpl
├── Caddyfile.public        # generated from template by setup.sh
├── postgres/
│   └── init.sql
├── scripts/
│   ├── anythingllm-entrypoint.sh
│   ├── setup.sh
│   └── stack.sh
├── secrets/
│   └── postgres_password.txt
└── storage/
    ├── anythingllm/
    └── postgres/
```

## Local HTTPS mode

Use this mode if you do not have a domain.

### Address

```text
https://anythingllm.localhost
```

### Caddyfile.local

```caddyfile
https://anythingllm.localhost {
    tls internal
    encode gzip

    header {
        Strict-Transport-Security "max-age=31536000"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        -Server
    }

    reverse_proxy anythingllm:3001
}
```

Caddy's internal CA provides locally trusted HTTPS without needing public DNS.

## Public HTTPS mode

Use this mode if you have a real domain.

### Example domain

```text
llm.example.com
```

### Caddyfile.public.tmpl

The template uses `{{PUBLIC_DOMAIN}}` as a placeholder; `setup.sh` renders it to `Caddyfile.public` with the domain you enter. Example rendered output for `llm.example.com`:

```caddyfile
llm.example.com {
    encode gzip

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        -Server
    }

    reverse_proxy anythingllm:3001
}
```

Point DNS for your domain to this host, then start public mode. Caddy will manage a public certificate automatically when the domain is reachable.

## Operations

Always drive the stack through `scripts/stack.sh`. It selects the correct `Caddyfile` for the mode, writes `CADDYFILE_PATH` into `.env`, then forwards the remaining arguments to `docker compose`. The first argument is the mode (`local` or `public`); everything after it is passed through verbatim.

```text
./scripts/stack.sh {local|public} <docker compose args...>
```

### Start

```bash
./scripts/stack.sh local up -d      # local HTTPS via anythingllm.localhost
./scripts/stack.sh public up -d     # public HTTPS via your domain
```

### Stop (preserve containers and data)

```bash
./scripts/stack.sh local stop
```

### Restart

```bash
./scripts/stack.sh local restart
```

Restart a single service (e.g., after editing the Caddyfile):

```bash
./scripts/stack.sh local restart caddy
```

### Status and logs

```bash
./scripts/stack.sh local ps
./scripts/stack.sh local logs -f
./scripts/stack.sh local logs -f anythingllm
```

### Teardown

Remove containers and the network, keep host-mounted data:

```bash
./scripts/stack.sh local down
```

Also remove Caddy's named volumes (certificates and config cache). Host storage under `storage/` is unaffected:

```bash
./scripts/stack.sh local down -v
```

To wipe AnythingLLM and PostgreSQL data as well, delete the host directories referenced by `ANYTHINGLLM_STORAGE` and `POSTGRES_STORAGE` in `.env` after running `down`.

### Switching modes

Run `stack.sh` with the new mode — it rewrites `CADDYFILE_PATH` in `.env`. Then restart Caddy so it reloads the new Caddyfile:

```bash
./scripts/stack.sh public up -d
./scripts/stack.sh public restart caddy
```

## Changing storage paths

Edit `.env` if you want custom paths:

```env
ANYTHINGLLM_STORAGE=/your/custom/path/anythingllm
POSTGRES_STORAGE=/your/custom/path/postgres
```

You can also re-run `scripts/setup.sh` and choose custom values when prompted.

## Using a host LLM provider (Ollama, LocalAI, LM Studio)

You can point AnythingLLM at a model server running on the host — no need to containerize it. Inside the container, use `host.docker.internal` (the Compose file already maps it on Linux via `extra_hosts: host-gateway`):

- Ollama: `http://host.docker.internal:11434`
- LocalAI: `http://host.docker.internal:8080`
- LM Studio: `http://host.docker.internal:1234`

Make sure the provider listens on `0.0.0.0`, not `127.0.0.1`:

- **Ollama**: set `OLLAMA_HOST=0.0.0.0:11434` before starting (e.g., `launchctl setenv OLLAMA_HOST "0.0.0.0:11434"` on macOS).
- **LM Studio**: enable "Serve on Local Network" in the server tab.
- **LocalAI**: binds to `0.0.0.0` by default.

## Security notes

- Keep PostgreSQL private to the Docker network.
- Do not commit `secrets/postgres_password.txt`.
- Back up both storage directories.
- Use local mode for private access and public mode only when you need internet-facing HTTPS.

## Troubleshooting

- If `anythingllm.localhost` does not resolve, confirm the hosts entry exists.
- If PostgreSQL fails on first boot, make sure the storage directory is empty.
- If AnythingLLM cannot connect to PostgreSQL, confirm the secret exists and the DB host is `postgres`.
- If you switch modes, restart the proxy container so Caddy reloads (`./scripts/stack.sh <mode> restart caddy`).
- If `docker compose` commands warn that `CADDYFILE_PATH` is unset, run any `./scripts/stack.sh <mode> ...` command once — it writes the value into `.env` so subsequent bare `docker compose` calls inherit it.

## References

Sources consulted while building and troubleshooting this stack:

### AnythingLLM
- [AnythingLLM — Available Docker Images (incl. the `pg` variant)](https://docs.anythingllm.com/installation-docker/available-images)
- [AnythingLLM — Local Docker installation](https://docs.anythingllm.com/installation-docker/local-docker)
- [AnythingLLM — Cloud Docker installation](https://docs.anythingllm.com/installation-docker/cloud-docker)
- [AnythingLLM — Docker quickstart](https://docs.anythingllm.com/installation-docker/quickstart)
- [Mintplex-Labs/anything-llm (GitHub)](https://github.com/Mintplex-Labs/anything-llm)
- [Upstream `docker/docker-compose.yml`](https://github.com/Mintplex-Labs/anything-llm/blob/master/docker/docker-compose.yml)
- [Issue #2057 — Using a single PostgreSQL database for AnythingLLM data + vectors](https://github.com/Mintplex-Labs/anything-llm/issues/2057)

### PostgreSQL + pgvector
- [`pgvector/pgvector` Docker image](https://hub.docker.com/r/pgvector/pgvector)
- [Alibaba Cloud — AnythingLLM with RDS PostgreSQL pgvector](https://www.alibabacloud.com/blog/anythingllm-builds-personal-knowledge-bases-with-rds-postgresqls-pgvector-plug-in_602502)
- [DEV — Setting up PostgreSQL with pgvector using Docker](https://dev.to/yukaty/setting-up-postgresql-with-pgvector-using-docker-hcl)
- [Automating Postgres + pgvector setup with Docker](https://alpeshkumar.com/docker/automating-postgres-and-pgvector-setup-with-docker/)

### Walkthroughs / community guides
- [Revold — How to Install and Set Up AnythingLLM on Docker](https://blog.revold.us/how-to-install-and-set-up-anythingllm-on-docker/)
- [DEV — RAG Tutorial: Exploring AnythingLLM and Vector Admin](https://dev.to/worldlinetech/rag-tutorial-exploring-anythingllm-and-vector-admin-4i3c)

### Reverse proxy
- [Caddy v2 documentation](https://caddyserver.com/docs/)
- [Caddy `tls internal` (local HTTPS)](https://caddyserver.com/docs/caddyfile/directives/tls#internal)
