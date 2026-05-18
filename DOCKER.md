# Contest Management System (CMS) - Docker Environment Guide

This guide provides instructions on how to set up, run, and maintain the Contest Management System (CMS) using the Docker environment. By leveraging Docker, you can run the complex distributed grader and services of CMS in an isolated, pre-configured sandbox without conflicting with host libraries.

---

## 🛠️ Quick Start

### 1. Environment Setup
To automatically install Docker, Docker Compose, and configure all non-root permissions and BuildKit requirements on your Debian-based system (e.g. Deepin 25, Debian, or Ubuntu), run the master setup script:
```bash
sudo ./setup_docker.sh
```

### 2. Apply Group Permissions
Once the setup finishes, update your terminal session groups so you can run Docker without typing `sudo` every time:
```bash
newgrp docker
```
*(Alternatively, you can log out of your Linux session and log back in to apply this globally).*

### 3. Launch Development Mode
Launch the integrated development environment (running standard Postgres and the development version of CMS):
```bash
./docker/cms-dev.sh
```

---

## 📂 Configuration & Launcher Structure

The Docker configuration consists of the following structure in the repository:
- **[Dockerfile](Dockerfile)**: The build environment blueprint. Creates a non-root `cmsuser` user, installs all compilation and runtime languages (C++, Java, Rust, Haskell, PHP, PyPy, Pascal, Mono), compiles the sandbox compiler (`isolate`), and sets up a Python virtual environment.
- **[docker/docker-compose.dev.yml](docker/docker-compose.dev.yml)**: The development environment configuration mapping two core services:
  - `devdb`: Postgres 15 database instance using host bind mounts for persistent data storage.
  - `devcms`: The CMS development container running in privileged mode to allow `isolate` to use Linux namespaces.
- **[docker/cms-dev.sh](docker/cms-dev.sh)**: A launcher script that builds/spins up the development container and opens an interactive bash prompt.
- **[docker/cms-test.sh](docker/cms-test.sh)**: Runs the CMS unit and functional test suites.
- **[docker/cms-stresstest.sh](docker/cms-stresstest.sh)**: Runs specialized stress-testing suites against dummy contest objects.

---

## 🎮 Working Inside the CMS Container

When you run `./docker/cms-dev.sh`, you are automatically connected to the running container bash shell as `cmsuser` in the `/home/cmsuser/src` workspace. 

### 1. Database Initialization
Before running CMS for the first time, you must initialize the database schema inside the container:
```bash
# Deletes old schema and configures a clean PostgreSQL schema
cmsInitDB
```

### 2. Adding an Administrator
Add your first admin account to access the CMS Admin Web Server:
```bash
# Replace 'myusername' and 'mypassword' with your preferred credentials
cmsAddAdmin -p mypassword myusername
```

### 3. Running Services
CMS is distributed, meaning its services run separately. To run a fully local environment for testing, open multiple tabs or run them in the background:
```bash
# Start the core logging service
cmsLogService &

# Start the administrative interface (available on http://localhost:8889)
cmsAdminWebServer &

# Start the contest interface for contestants (available on http://localhost:8888)
cmsContestWebServer &

# Start a worker daemon to evaluate submissions
cmsWorker 0 &
```

---

## 🧪 Testing

To run the unit tests and functional test suite inside the sandboxed test database environment, simply execute:
```bash
./docker/cms-test.sh
```
This builds a fresh copy, runs the unit test configurations with `pytest`, outputs JUnit results, and cleans up the test schemas automatically.

---

## 🧹 Troubleshooting & Maintenance

### Permission Denied to Docker Socket
If you see the error `permission denied while trying to connect to the docker API`, verify your user is in the `docker` group:
```bash
groups
```
If `docker` is not listed, make sure to execute:
```bash
sudo usermod -aG docker $USER
# Then restart your shell or terminal
exec bash
```

### Resetting the Database Volume
If the Postgres database gets corrupted or you want a 100% fresh environment, stop the container and delete the persistent database folder:
```bash
docker compose -p cms-main -f docker/docker-compose.dev.yml down -v
rm -rf .dev/postgres-data
```

### Rebuilding from Scratch
To ignore all cached layers and force a clean, from-scratch image compile of all languages and system libraries:
```bash
DOCKER_BUILDKIT=1 docker compose -f docker/docker-compose.dev.yml build --no-cache devcms
```
