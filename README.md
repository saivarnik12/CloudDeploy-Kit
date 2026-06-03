# CloudDeploy Kit ☁️

> A production-ready DevOps infrastructure project featuring CI/CD pipelines, Docker containerization, Nginx reverse proxy, health monitoring, SSL automation, and zero-downtime blue-green deployments.

![Docker](https://img.shields.io/badge/Docker-24.x-blue)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-CI%2FCD-green)
![Nginx](https://img.shields.io/badge/Nginx-1.25-red)
![Node.js](https://img.shields.io/badge/Node.js-18-brightgreen)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15-blue)
![Redis](https://img.shields.io/badge/Redis-7-red)

**Live Demo:** [saivarnik12.github.io/CloudDeploy-Kit](https://saivarnik12.github.io/CloudDeploy-Kit/)

---

## What's in this project

| Component | Status | Details |
|---|---|---|
| Docker | ✅ Present | Multi-stage prod + dev Dockerfiles |
| Nginx | ✅ Present | Reverse proxy, SSL, rate limiting |
| GitHub Actions | ✅ Present | CI + CD + GitHub Pages pipelines |
| Deploy Scripts | ✅ Present | Blue-green deploy, rollback, health check |
| Application Code | ✅ Added | Node.js/Express REST API, JWT auth, tasks CRUD |
| Monitoring | ✅ Added | Uptime monitor, Prometheus, alert rules |
| SSL Automation | ✅ Added | Let's Encrypt via Certbot + auto-renewal cron |
| Environment Configs | ✅ Added | dev / staging / production .env templates |
| Dev/Test Compose | ✅ Added | Hot reload dev, isolated test environment |
| Architecture Diagram | ✅ Added | Mermaid diagram in docs/ |
| GitHub Pages Demo | ✅ Added | docs/index.html with auto-deploy workflow |

---

## Quick Start

### Development (hot reload)
```bash
git clone https://github.com/yourusername/clouddeploy-kit.git
cd clouddeploy-kit

# Start dev (hot reload, pgAdmin :5050, Redis Commander :8081)
docker-compose -f docker-compose.dev.yml up --build

# With debug tools
docker-compose -f docker-compose.dev.yml --profile tools up
```

### Run Tests
```bash
docker-compose -f docker-compose.test.yml up --abort-on-container-exit
```

### Production Deploy
```bash
# 1. Bootstrap VPS (run once on a fresh Ubuntu server)
sudo bash scripts/setup-server.sh

# 2. Get SSL certificate
./scripts/ssl-setup.sh obtain yourdomain.com admin@yourdomain.com

# 3. Deploy
./scripts/deploy.sh production v1.0.0

# 4. Health check
./scripts/health-check.sh

# 5. Rollback if needed
./scripts/rollback.sh production
```

---

## Project Structure

```
CloudDeploy-Kit/
├── .github/workflows/
│   ├── ci.yml                  # lint + test on every PR
│   ├── cd.yml                  # build + deploy on main merge
│   └── pages.yml               # GitHub Pages deployment
├── app/                        # ← Application code
│   ├── src/
│   │   ├── server.js           # Express entry point
│   │   ├── routes/             # health, auth, tasks
│   │   └── middleware/         # auth JWT, errorHandler, logger
│   ├── database/schema.sql     # users + tasks tables
│   └── package.json
├── src/
│   ├── Dockerfile              # Multi-stage production
│   └── Dockerfile.dev          # Dev with hot reload
├── nginx/
│   ├── nginx.conf              # Worker config, gzip, logging
│   └── conf.d/app.conf         # SSL, proxy, rate limiting
├── scripts/
│   ├── deploy.sh               # Zero-downtime blue-green deploy
│   ├── rollback.sh             # Revert to previous version
│   ├── health-check.sh         # Verify all services
│   ├── ssl-setup.sh            # Let's Encrypt automation
│   └── setup-server.sh         # One-time VPS bootstrap
├── monitoring/
│   ├── uptime-monitor.sh       # Continuous polling + Slack alerts
│   ├── prometheus.yml          # Prometheus scrape config
│   └── alert_rules.yml         # Alert definitions
├── environments/
│   ├── .env.development
│   ├── .env.staging
│   └── .env.production         # Template — use GitHub Secrets for real values
├── docs/
│   ├── index.html              # GitHub Pages demo
│   └── architecture.mermaid    # System architecture
├── docker-compose.yml          # Production
├── docker-compose.dev.yml      # Development
├── docker-compose.test.yml     # Isolated CI tests
└── README.md
```

---

## CI/CD Pipeline

```
Push → lint → test (docker-compose.test.yml) → docker build
     → push GHCR → ssh VPS → deploy.sh (blue-green swap)
     → health check → [pass] done | [fail] auto rollback
```

---

## Blue-Green Deployment

`deploy.sh` implements zero-downtime deploys:
1. Pull new image from GHCR
2. Start green container on port 5001
3. Health check green (retry 10× / 5s)
4. Pass: reload Nginx upstream → switch traffic to green → stop blue
5. Fail: stop green, blue keeps serving — zero downtime

---

## API Endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | /health | — | Liveness probe |
| GET | /health/ready | — | Readiness (DB + Redis check) |
| POST | /api/auth/register | — | Create account |
| POST | /api/auth/login | — | Login → JWT tokens |
| POST | /api/auth/refresh | — | Refresh access token |
| GET | /api/tasks | Bearer | List tasks (paginated) |
| POST | /api/tasks | Bearer | Create task |
| PUT | /api/tasks/:id | Bearer | Update task |
| DELETE | /api/tasks/:id | Bearer | Delete task |

---

## License — MIT
