# CMS Docker Guide – Complete Reference

> **Audience**: Developers and contest organizers who want to run the Contest Management System (CMS) inside Docker containers. This guide assumes you have already run `setup_docker.sh` and have the Docker environment ready.

---

## 📦 Table of Contents
1. [Project Layout Overview](#project-layout-overview)
2. [Starting the Development Stack](#starting-the-development-stack)
3. [Understanding the Compose Services](#understanding-the-compose-services)
4. [Database Initialization – Common Pitfalls & Fixes](#database-initialization-common-pitfalls--fixes)
5. [Running CMS Commands Inside the Container](#running-cms-commands-inside-the-container)
6. [Resetting / Re‑initialising the PostgreSQL Volume](#resetting--re‑initialising-the-postgresql-volume)
7. [Exposing the Contest Web Server to the Internet](#exposing-the-contest-web-server-to-the-internet)
8. [Production‑Ready Exposure (Reverse Proxy / Cloudflare Tunnel)](#production‑ready-exposure-reverse-proxy--cloudflare-tunnel)
9. [FAQ & Troubleshooting Checklist](#faq--troubleshooting-checklist)

---

## 1️⃣ Project Layout Overview
```
cms/                       # repository root
├─ Dockerfile               # builds the CMS image (includes isolate, languages, venv)
├─ docker/                  # helper scripts & compose files
│   ├─ cms-dev.sh          # launch dev environment (auto‑cd to repo root)
│   ├─ cms-test.sh         # run unit & functional tests
│   ├─ cms-stresstest.sh   # run stress‑test suite
│   ├─ docker-compose.dev.yml   # dev stack (devdb + devcms)
│   └─ docker-compose.test.yml  # test stack (testdb + testcms)
├─ setup_docker.sh         # master installer (Docker CE, BuildKit, user group)
├─ DOCKER.md               # quick‑start guide (this file)
└─ Docker_Guide.md         # **full** Docker‑specific documentation (this file)
```

All scripts in `docker/` are **directory‑independent** – they resolve the repository root automatically, so you can invoke them from anywhere (project root, `docker/` subdirectory, or a separate terminal).

---

## 2️⃣ Starting the Development Stack
```bash
# From the repository root (or any sub‑directory)
./docker/cms-dev.sh
```
The script will:
1. Detect the current Git branch (e.g. `main`).
2. Enable BuildKit (`DOCKER_BUILDKIT=1`).
3. Run `docker compose` with the dev compose file.
4. Mount the repository source into the container (`/home/cmsuser/src`).
5. Expose PostgreSQL on ports **8888‑8890** (see section *Understanding the Compose Services*).

If everything starts correctly you will land in an **interactive bash** inside the container as `cmsuser`:
```bash
cmsuser@<container-id>:/home/cmsuser/src$ 
```
From here you can run any CMS command (`cmsInitDB`, `cmsAddAdmin`, etc.).

---

## 3️⃣ Understanding the Compose Services
| Service | Image | Port(s) | Purpose |
|---------|-------|--------|---------|
| `devdb` | `postgres:15` | `8888‑8890` (internal) | PostgreSQL instance used by CMS. Data persisted in the host directory **`.dev/postgres-data`**. |
| `devcms` | Built from the repo `Dockerfile` | `8888` (ContestWebServer), `8889` (AdminWebServer), `8890` (RankingWebServer) | The actual CMS runtime. Runs **privileged** and with **cgroup: host** to allow the sandbox (`isolate`). |

> **Important**: Only expose the ContestWebServer (`8888`) publicly. The admin interface (`8889`) should stay behind a firewall or VPN.

---

## 4️⃣ Database Initialization – Common Pitfalls & Fixes
When you first start the stack, you need to **create the CMS database schema**. The most frequent error looks like this:
```
psycopg2.OperationalError) connection to server at "devdb" (172.18.0.2), port 5432 failed: FATAL:  database "cmsdb" does not exist
```
### Why does it happen?
* The **PostgreSQL container** `devdb` is up, but the **CMS container** cannot find the `cmsdb` database because it has not been created yet, or the connection string in `cms.sample.toml` points to a non‑existent DB name.

### Step‑by‑step fix
1. **Enter the CMS container** (you are already there after `cms-dev.sh`). If you are outside, run:
   ```bash
   docker compose -f docker/docker-compose.dev.yml exec devcms bash
   ```
2. **Check the configuration file** (`/home/cmsuser/cms/etc/cms-devdb.toml`). It should contain:
   ```toml
   [database]
   host = "devdb"
   port = 5432
   name = "cmsdb"
   user = "postgres"
   password = ""  # empty because `POSTGRES_HOST_AUTH_METHOD=trust`
   ```
   If the `name` field is something else (e.g. `cmsdbfortesting`), change it to `cmsdb`.
3. **Create the database and role** using the built‑in helper scripts:
   ```bash
   # Inside the CMS container
   cmsInitDB         # creates the DB and required roles automatically.
   ```
   This command runs the following steps internally:
   * `createdb -U postgres cmsdb`
   * `psql -U postgres -c "CREATE ROLE cmsuser LOGIN;"`
   * `psql -U postgres -d cmsdb -c "ALTER SCHEMA public OWNER TO cmsuser;"`
   * Grant permissions on large objects, etc.
4. **Verify the DB exists**:
   ```bash
   psql -U postgres -d cmsdb -c "\l"   # should list cmsdb
   ```
5. **If you still see the error**, the `devdb` container might not have finished initializing. Wait a few seconds after `docker compose up` and retry `cmsInitDB`.

### Manual DB creation (rarely needed)
If you prefer to run the commands yourself, use the container‑internal `psql` binary:
```bash
# Inside the container
psql -U postgres -c "CREATE DATABASE cmsdb;"
psql -U postgres -d cmsdb -c "CREATE ROLE cmsuser LOGIN;"
psql -U postgres -d cmsdb -c "ALTER SCHEMA public OWNER TO cmsuser;"
psql -U postgres -d cmsdb -c "GRANT SELECT ON pg_largeobject TO cmsuser;"
```
After that, re‑run `cmsInitDB` to let CMS apply its internal migrations.

---

## 5️⃣ Running CMS Commands Inside the Container
All CMS scripts (`cmsAddAdmin`, `cmsInitDB`, `cmsLogService`, …) are **exposed on the `$PATH`** inside the container. Example workflow:
```bash
# Inside the container after `cms-dev.sh`
# 1️⃣ Initialise the DB (only once)
cmsInitDB

# 2️⃣ Create an admin user (replace with your credentials)
cmsAddAdmin -p superSecretPass myadmin

# 3️⃣ Start the services you need (you can background them with &)
cmsLogService &
cmsAdminWebServer &   # keep this internal only!
cmsContestWebServer & # contestants will hit http://localhost:8888
cmsRankingWebServer &   # optional public scoreboard
cmsWorker 0 &          # start one worker daemon
```
**Tip**: Use `tmux` or `screen` inside the container if you want long‑running background services to survive when you detach from the container’s bash session.

---

## 6️⃣ Resetting / Re‑initialising the PostgreSQL Volume
Sometimes you need a **completely clean database** (e.g., after schema changes or a corrupted volume). Follow these steps:
```bash
# Stop the stack (this removes containers but keeps the volume)
./docker/cms-dev.sh  # press Ctrl‑C to stop

# Delete the persisted volume directory on the host
rm -rf .dev/postgres-data

# Restart the stack – Docker will recreate a fresh DB instance
./docker/cms-dev.sh

# Inside the new container, initialise the DB again
cmsInitDB
```
If you simply want to drop *and* recreate the DB without deleting the host volume, you can run inside the container:
```bash
# Drop the existing DB (cautious – this destroys all data!)
dropdb --if-exists --host=devdb --username=postgres cmsdb
createdb --host=devdb --username=postgres cmsdb
cmsInitDB   # re‑apply migrations
```
---

## 7️⃣ Exposing the Contest Web Server to the Internet (Quick Way)
The dev stack already **binds the ports to the host** (`8888`, `8889`, `8890`). To make them reachable from outside your LAN you need to:
1. **Open the ports on your firewall** (UFW example):
   ```bash
   sudo ufw allow 8888/tcp   # contest UI – **public**
   sudo ufw allow 8890/tcp   # scoreboard – optional public
   # Do NOT open 8889 (admin) unless you restrict it to a VPN IP range.
   ```
2. **Configure your router** to forward those ports to the machine running Docker (your laptop’s LAN IP). Most home routers have a *Port Forwarding* section – map external port `8888` → internal `8888` (TCP) of your machine’s IP.
3. **Secure with HTTPS** – browsers will block the UI if served over plain HTTP on a public domain. The easiest way is to use a **Cloudflare Tunnel** (see section 8) or a reverse proxy that gets a free Let’s Encrypt certificate.

> **Safety Note**: Never expose the admin port (`8889`) to the public internet. If you must access it remotely, use an SSH tunnel:
> ```bash
> ssh -L 8889:localhost:8889 youruser@your‑server
> ```
> Then open `http://localhost:8889` on your local machine.

---

## 8️⃣ Production‑Ready Exposure (Reverse Proxy or Cloudflare Tunnel)
### Option A – Cloudflare Tunnel (Zero‑config, HTTPS, DDoS protection)
1. Install `cloudflared` on the host (already described in the **Exposing** section of the previous guide). 
2. Create a tunnel and point **`contest.yourdomain.com`** to `http://localhost:8888`.
3. Cloudflare automatically provisions a TLS certificate.
4. You can also expose the scoreboard on `scoreboard.yourdomain.com`.
5. No port‑forwarding or firewall changes are needed – traffic flows through Cloudflare’s edge network and then through the outbound tunnel.

### Option B – Reverse Proxy with Caddy (auto‑TLS)
1. **Install Caddy** on the host:
   ```bash
   sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
   curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
   curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
   sudo apt update && sudo apt install caddy
   ```
2. Edit `/etc/caddy/Caddyfile`:
   ```caddy
   contest.example.com {
       reverse_proxy localhost:8888
   }
   scoreboard.example.com {
       reverse_proxy localhost:8890
   }
   ```
3. Restart Caddy: `sudo systemctl restart caddy`.
4. Caddy will automatically request a **Let’s Encrypt** cert for `contest.example.com` and `scoreboard.example.com` and serve them over HTTPS.
5. Ensure ports **80** and **443** are open on your firewall (UFW: `sudo ufw allow 80,443/tcp`).

---

## 9️⃣ FAQ & Troubleshooting Checklist
| Symptom | Likely Cause | Fix |
|---|---|---|
| `FATAL: database "cmsdb" does not exist` | DB not created / `cms.sample.toml` points to wrong name | Run `cmsInitDB` inside container; verify `cms‑devdb.toml` `name = "cmsdb"` |
| `role "cmsuser" does not exist` | Role not created (usually by `cmsInitDB`) | Ensure you run `cmsInitDB`; or manually `createrole cmsuser login;` |
| `connection to server at "devdb" … failed` | PostgreSQL container not ready yet | Wait a few seconds after `docker compose up`; `docker logs <devdb>` to see when it’s ready. |
| `permission denied while trying to connect to the docker API` | Current shell not in `docker` group | Run `newgrp docker` or reopen terminal. |
| Port 8888 unreachable from outside | Firewall / router not forwarding | Open port in UFW; forward in router; or use Cloudflare tunnel. |
| Admin UI reachable publicly | Mis‑configuration – you opened port 8889 | Close port 8889; keep admin UI local only. |
| `psql: could not connect to server` inside container | `psql` binary trying to use socket instead of TCP | Always use `-h devdb -U postgres` to force TCP. |

---

## 🎯 Quick Start Recap (All in One Script)
```bash
# 1️⃣ Install Docker & configure user (run once)
sudo ./setup_docker.sh
newgrp docker   # refresh group membership

# 2️⃣ Launch dev environment (exposes ports 8888‑8890)
./docker/cms-dev.sh   # you land inside the container

# 3️⃣ Inside the container – initialise DB and create admin
cmsInitDB
cmsAddAdmin -p SuperSecretPass myadmin

# 4️⃣ Start services (you can background them with &)
cmsLogService &
cmsContestWebServer &   # public URL: http://<host-ip>:8888
cmsRankingWebServer &    # optional: http://<host-ip>:8890
cmsWorker 0 &

# 5️⃣ OPTIONAL – expose to internet via Cloudflare (run on host)
cloudflared tunnel run cms-tunnel   # after you set up the tunnel as described above
```
You now have a fully functional, internet‑reachable CMS contest environment!

---

*All commands are written for a **Debian‑based** host (Deepin 25, Ubuntu, Debian). Adjust package names if you use a different distribution.*

---

*Happy contest hosting!* 🎉
