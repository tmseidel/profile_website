---
layout: article.njk
title: "Running Docker Engine in WSL2 alongside Docker Desktop for Windows"
description: "A practical guide to running both Docker Engine natively in WSL2 and Docker Desktop for Windows in complete isolation — diagnosing conflicts, fixing networking issues, and configuring coexistence."
date: 2026-04-11
tags:
  - articles
  - Docker
  - WSL2
  - DevOps
  - Windows
---

This guide explains why you might need both Docker Engine (installed natively in WSL2) and Docker Desktop for Windows, what conflicts arise when both are present, and how to configure them to run in complete isolation.

## Why You Need Both

### Docker Engine in WSL2 — For Local Development

For local development and testing, you run containers directly in WSL2 using the native Docker Engine (installed via `apt` from Docker's official repository).

Key advantages:
- Containers share the WSL2 network stack — `host.docker.internal:host-gateway` routes to the real host IP (`172.x.x.x`), so containers can reach services running on the host (e.g., a web server on port 8080)
- Fast, lightweight, and fully Linux-native
- No dependency on a Windows GUI application

### Docker Desktop — Why It Might Be Installed

There are several reasons why you might also have Docker Desktop for Windows installed:

- **Remote SSH deployments from Windows:** Docker Compose supports deploying to remote servers via SSH contexts (`docker context create my-server --docker "host=ssh://user@server"`). When running this from a **Windows terminal** (PowerShell, CMD), Docker Desktop provides the Docker daemon. While SSH-based Docker contexts work perfectly fine from native Linux (including WSL2), some workflows require running `docker compose` from the Windows side — e.g., CI/CD scripts running on Windows, or using Windows-native tooling.
- **Windows container support:** Docker Desktop can run Windows containers (for .NET Framework apps, IIS, etc.), which Docker Engine in WSL2 cannot.
- **GUI-based management:** Docker Desktop provides a graphical dashboard for container management, image browsing, and resource configuration.
- **Corporate/team requirement:** Your organization may standardize on Docker Desktop for license compliance or support reasons.
- **Kubernetes integration:** Docker Desktop includes a single-node Kubernetes cluster for local testing.

The key point is: **you don't need to uninstall Docker Desktop** — you just need to prevent it from interfering with the Docker Engine in WSL2.

### Summary

| Use Case | Tool | Where to Run |
|----------|------|-------------|
| Local development containers | Docker Engine in WSL2 | WSL2 terminal |
| Host service + container integration testing | Docker Engine in WSL2 | WSL2 terminal |
| SSH remote deployment from WSL2 | Docker Engine in WSL2 | WSL2 terminal |
| Windows containers, GUI management, K8s | Docker Desktop | Windows terminal / PowerShell |
| Corporate/team-mandated Docker usage on Windows | Docker Desktop | Windows terminal / PowerShell |

## The Conflict

When Docker Desktop is installed, it enables **WSL2 Integration** by default (Settings → Resources → WSL Integration). This injects Docker Desktop's own binaries and configuration into your WSL2 distro, overriding the native Docker Engine. The two cannot coexist when this integration is active.

### What Goes Wrong

| Symptom | Cause |
|---------|-------|
| `host.docker.internal` resolves to `192.168.65.254` instead of `172.17.0.1` | Docker Desktop routes through its internal VM gateway, not the WSL2 bridge |
| `curl http://host.docker.internal:<port>` fails from containers | The VM gateway (`192.168.65.254`) does not forward to WSL2 host ports |
| `/run/docker.sock` or `/var/run/docker.sock` does not exist | Docker Desktop replaces the socket with its own, and the native `docker.socket` systemd unit gets confused |
| `docker context ls` shows `desktop-linux` context | Docker Desktop injected its context into WSL2 |
| `docker ps` shows different containers than expected | CLI is talking to Docker Desktop's daemon instead of the local one |
| Webhooks or callbacks from containers never reach a host service | Container → `host.docker.internal` → Docker Desktop VM → **dead end** (not forwarded to WSL2) |
| `--network host` still doesn't reach host services | On Docker Desktop, `host` mode connects to the VM's network, not WSL2's |

### Understanding the Routing Problem

When a container needs to reach a service on your WSL2 host (e.g., a web application running on port 8080), it uses `host.docker.internal`. How this hostname resolves determines whether the connection works.

**With Docker Desktop WSL2 Integration (broken):**
```
Container
  → host.docker.internal (192.168.65.254)
    → Docker Desktop VM
      → Windows host
        ✘ WSL2 host (not forwarded)
```

The traffic goes through Docker Desktop's internal VM, reaches the Windows host, but is never forwarded to the WSL2 instance where your service is actually running.

**With native Docker Engine in WSL2 (working):**
```
Container
  → host.docker.internal (172.17.0.1)
    → WSL2 host ✔ (direct bridge route)
```

The traffic goes directly over the Docker bridge network to the WSL2 host — no intermediate VM, no forwarding issues.

## Diagnosis

If you suspect Docker Desktop is interfering with your WSL2 Docker Engine, run these commands inside your WSL2 terminal:

### 1. Check which Docker binary is active

```bash
which docker
ls -la $(which docker)
```

- ✅ Native: `/usr/bin/docker` owned by `root`
- ❌ Desktop override: symlink to `/mnt/wsl/docker-desktop/...` or similar

### 2. Check Docker contexts

```bash
docker context ls
```

- ✅ Only `default` pointing to `unix:///var/run/docker.sock`
- ❌ A `desktop-linux` context exists (Docker Desktop injected it)

### 3. Check the Docker socket

```bash
ls -la /run/docker.sock
```

- ✅ Socket file exists: `srw-rw---- root docker ... /run/docker.sock`
- ❌ File does not exist, or is a symlink to a Docker Desktop path

### 4. Check `host.docker.internal` from inside a container

```bash
docker run --rm --add-host=host.docker.internal:host-gateway \
  busybox cat /etc/hosts | grep host.docker
```

- ✅ `172.17.0.1  host.docker.internal` (WSL2 Docker bridge gateway)
- ❌ `192.168.65.254  host.docker.internal` (Docker Desktop VM gateway)

### 5. Test container-to-host connectivity

If you have a service running on the host (e.g., on port 8080):

```bash
docker run --rm --add-host=host.docker.internal:host-gateway \
  curlimages/curl curl -s -o /dev/null -w "HTTP %{http_code}" \
  --connect-timeout 3 http://host.docker.internal:8080/
```

- ✅ `HTTP 200` (or any non-zero HTTP status)
- ❌ `HTTP 000` (connection failed)

## Resolution

### Step 1: Disable Docker Desktop WSL2 Integration

This is the critical step. In Docker Desktop:

1. Open **Docker Desktop**
2. Go to **Settings → Resources → WSL Integration**
3. **Disable** "Enable integration with my default WSL distro"
4. **Disable** the toggle for your Ubuntu (or other) WSL2 distro
5. Click **Apply & Restart**

Docker Desktop will continue working from Windows terminals (PowerShell, CMD), but it will stop injecting itself into WSL2.

### Step 2: Remove the Docker Desktop context from WSL2

```bash
docker context rm desktop-linux
```

Verify only the native context remains:

```bash
docker context ls
```

Expected output:
```
NAME        DESCRIPTION                               DOCKER ENDPOINT
default *   Current DOCKER_HOST based configuration   unix:///var/run/docker.sock
```

### Step 3: Restart the native Docker Engine

If the Docker socket is missing after disabling Desktop integration:

```bash
sudo systemctl stop docker docker.socket
sudo systemctl start docker.socket
sudo systemctl start docker
```

Verify the socket exists:

```bash
ls -la /run/docker.sock
# Expected: srw-rw---- 1 root docker 0 ... /run/docker.sock
```

### Step 4: Verify container-to-host connectivity

Start any service on the host (or use a simple test server), then:

```bash
# Quick test: start a temporary HTTP server on the host
python3 -m http.server 9999 &
TEST_PID=$!

# Test from a container
docker run --rm --add-host=host.docker.internal:host-gateway \
  curlimages/curl curl -s -o /dev/null -w "HTTP %{http_code}" \
  --connect-timeout 3 http://host.docker.internal:9999/

# Clean up
kill $TEST_PID
```

Expected result: `HTTP 200`

### Step 5: Recreate your running containers

Existing containers were created under the old networking configuration. You need to recreate them for the fix to take effect:

```bash
docker compose -f <your-compose-file.yml> down
docker compose -f <your-compose-file.yml> up -d
```

> **Note:** If your compose file uses named volumes and you're also changing container image versions, you may need `down -v` to remove old volumes. Only use `-v` if you don't mind losing persisted data.

## Running in Isolation

After completing the resolution steps, the two Docker installations run independently:

| | Docker Engine (WSL2) | Docker Desktop (Windows) |
|---|---|---|
| **Access from** | WSL2 terminal (`bash`) | Windows terminal (PowerShell, CMD) |
| **Daemon** | `dockerd` via systemd in WSL2 | Docker Desktop VM |
| **Socket** | `/run/docker.sock` | `npipe:////./pipe/docker_engine` |
| **Containers** | Separate set | Separate set |
| **Networks** | WSL2 bridge (`172.17.0.0/16`) | Desktop VM bridge (`192.168.65.0/24`) |
| **`host.docker.internal`** | `172.17.0.1` (WSL2 host) | `192.168.65.254` (Windows host) |
| **Use for** | Local dev, testing, SSH deployments | Windows containers, GUI, K8s |

### Using Docker Desktop from Windows

When you need Docker Desktop features (Windows containers, GUI, Kubernetes), open **PowerShell** (not WSL2):

```powershell
# In PowerShell / Windows Terminal
docker ps
docker compose -f docker-compose.yml up -d
```

### Using Docker Engine from WSL2

For local development, use your WSL2 terminal as usual:

```bash
# In WSL2 bash
docker compose -f docker-compose.yml up -d
```

## Ensuring Docker Starts on WSL2 Boot

WSL2 doesn't always start systemd services automatically. To ensure Docker Engine is available when you open a WSL2 terminal:

```bash
# Enable Docker to start with systemd
sudo systemctl enable docker.service
sudo systemctl enable docker.socket
```

If your WSL2 distro doesn't have systemd enabled, add this to `/etc/wsl.conf`:

```ini
[boot]
systemd=true
```

Then restart WSL2 from PowerShell:

```powershell
wsl --shutdown
```

## Troubleshooting

### "Interactive authentication required" when starting Docker

```
Failed to start docker.service: Interactive authentication required.
```

You ran `systemctl start docker` without `sudo`. Use:

```bash
sudo systemctl start docker
```

To avoid needing `sudo` for Docker commands (not for systemctl), add your user to the `docker` group:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

### Docker socket disappears after reboot

Docker Desktop's WSL2 integration was re-enabled (e.g., after a Docker Desktop update), or the systemd socket unit didn't start. Check and fix:

```bash
# Check if Desktop integration is back
docker context ls  # Should NOT show desktop-linux

# Restart the socket
sudo systemctl restart docker.socket docker
ls -la /run/docker.sock
```

If `desktop-linux` reappeared, Docker Desktop re-enabled WSL2 integration — repeat [Step 1](#step-1-disable-docker-desktop-wsl2-integration) of the resolution.

### Container can ping `host.docker.internal` but can't connect to a port

The hostname resolves but the port is unreachable. Verify:

1. **The service is actually running on the host:**
   ```bash
   curl http://localhost:<port>/
   ```

2. **Check what IP the container sees:**
   ```bash
   docker exec <container-name> cat /etc/hosts | grep host.docker
   ```
   - If `192.168.65.254` → Docker Desktop is still interfering (see [Resolution](#resolution))
   - If `172.17.0.1` → the service might not be running, might be bound to `127.0.0.1` only, or a firewall is blocking

3. **Verify the service listens on all interfaces:**
   ```bash
   ss -tlnp | grep <port>
   ```
   - ✅ `*:<port>` or `0.0.0.0:<port>` — listening on all interfaces
   - ❌ `127.0.0.1:<port>` — only localhost; reconfigure the service to bind to `0.0.0.0`

### `docker compose` shows containers from the wrong Docker

If `docker ps` in WSL2 shows containers you created in Docker Desktop (or vice versa), the wrong context is active:

```bash
docker context ls       # Check which context is active (marked with *)
docker context use default   # Switch to native WSL2 Docker
```

### Docker Desktop updates re-enable WSL2 integration

Docker Desktop may re-enable WSL2 integration after updates. If things suddenly break again after a Docker Desktop update, re-check Settings → Resources → WSL Integration and disable it again. Consider disabling Docker Desktop auto-updates if this becomes a recurring issue.



