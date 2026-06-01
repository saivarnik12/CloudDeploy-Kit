# CloudDeploy Kit ☁️

> A production-ready DevOps infrastructure project featuring CI/CD pipelines, Docker containerization, Nginx reverse proxy, health monitoring, and automated deployment scripts.

![Docker](https://img.shields.io/badge/Docker-24.x-blue) ![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-CI%2FCD-green) ![Nginx](https://img.shields.io/badge/Nginx-1.25-red) ![Shell](https://img.shields.io/badge/Shell-Bash-yellow)

---

## 📌 Overview

CloudDeploy Kit is a **DevOps infrastructure project** that demonstrates how to containerize a full-stack application, set up automated CI/CD pipelines, configure a production-grade Nginx reverse proxy, implement health monitoring, and automate deployments with zero-downtime rolling updates.

### This project demonstrates:
- **Docker & Docker Compose** — multi-service containerization
- **CI/CD Pipelines** — GitHub Actions (lint → test → build → deploy)
- **Nginx Configuration** — reverse proxy, SSL termination, rate limiting
- **Health Monitoring** — service health checks, uptime scripts
- **Zero-Downtime Deployment** — blue-green deployment strategy
- **Security Hardening** — Docker best practices, non-root users
- **Infrastructure as Code** — environment-specific configs
- **Shell Scripting** — deploy, rollback, health-check automation

---

## 🛠️ Tech Stack

| Component | Technology |
|-----------|-----------|
| Containerization | Docker 24, Docker Compose v3.8 |
| CI/CD | GitHub Actions |
| Reverse Proxy | Nginx 1.25 |
| Process Manager | Docker health checks |
| Monitoring | Custom shell health scripts |
| Secrets Management | GitHub Secrets + .env files |
| Registry | Docker Hub / GitHub Container Registry |

---

## ✨ Features

- ✅ Multi-stage Docker builds (smaller, secure images)
- ✅ GitHub Actions CI/CD pipeline (4 stages)
- ✅ Nginx reverse proxy with load balancing config
- ✅ SSL/TLS configuration (Let's Encrypt ready)
- ✅ Rate limiting and DDoS basic protection in Nginx
- ✅ Zero-downtime blue-green deployment script
- ✅ Automated rollback on failed health check
- ✅ Service health monitoring script with alerting
- ✅ Docker security best practices (non-root, read-only FS)
- ✅ Environment-specific configs (dev / staging / prod)

---

## 🚀 Quick Start

```bash
git clone https://github.com/yourusername/clouddeploy-kit.git
cd clouddeploy-kit

# Development
docker-compose -f docker-compose.dev.yml up --build

# Production (requires .env.prod)
./scripts/deploy.sh production v1.0.0

# Health check
./scripts/health-check.sh

# Rollback
./scripts/rollback.sh
```

---

## 📁 Project Structure

```
clouddeploy-kit/
├── .github/
│   └── workflows/
│       ├── ci.yml              # CI: lint + test on every PR
│       └── cd.yml              # CD: build + deploy on main merge
├── src/
│   ├── Dockerfile              # Multi-stage production Dockerfile
│   └── Dockerfile.dev          # Development Dockerfile
├── nginx/
│   ├── nginx.conf              # Main Nginx config
│   └── conf.d/
│       └── app.conf            # App-specific reverse proxy config
├── scripts/
│   ├── deploy.sh               # Zero-downtime deployment
│   ├── rollback.sh             # Quick rollback to previous version
│   ├── health-check.sh         # Service health verification
│   └── setup-server.sh         # One-time server bootstrap
├── monitoring/
│   └── uptime-monitor.sh       # Continuous health monitoring loop
├── docker-compose.yml          # Production compose
├── docker-compose.dev.yml      # Development compose
├── docker-compose.test.yml     # Test environment compose
└── README.md
```

---

## 🔄 CI/CD Pipeline

```
Push to feature branch
       │
       ▼
┌──────────────┐
│   CI Pipeline │
│  lint + test  │  ← Runs on every push/PR
└──────┬───────┘
       │
   Merge to main
       │
       ▼
┌──────────────┐
│  CD Pipeline  │
│ build image   │
│ push registry │
│ deploy prod   │  ← Zero-downtime rolling update
│ health check  │
│ rollback?     │
└──────────────┘
```

---

## 📄 License — MIT
