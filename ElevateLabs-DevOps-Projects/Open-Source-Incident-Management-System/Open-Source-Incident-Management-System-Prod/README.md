# IncidentHub — Open-Source Incident Management System

<p align="center">
  <img src="https://img.shields.io/badge/Python-3.11-blue?logo=python" alt="Python">
  <img src="https://img.shields.io/badge/Flask-3.0-green?logo=flask" alt="Flask">
  <img src="https://img.shields.io/badge/Docker-ready-2496ED?logo=docker" alt="Docker">
  <img src="https://img.shields.io/badge/SQLite-database-003B57?logo=sqlite" alt="SQLite">
  <img src="https://img.shields.io/badge/Bootstrap-5.3-7952B3?logo=bootstrap" alt="Bootstrap">
  <img src="https://img.shields.io/badge/license-MIT-brightgreen" alt="MIT License">
</p>

> A production-grade portal to log, track, assign, and resolve infrastructure & application incidents — with role-based access control, REST APIs, SMTP email notifications, and Docker support.

---

## Table of Contents

- [Features](#features)
- [Tech Stack](#tech-stack)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Docker Deployment](#docker-deployment)
- [REST API Reference](#rest-api-reference)
- [Role-Based Access Control](#role-based-access-control)
- [Email Notifications](#email-notifications)
- [Demo Credentials](#demo-credentials)
- [Project Structure](#project-structure)
- [Configuration](#configuration)
- [Sample Incidents](#sample-incidents)
- [Contributing](#contributing)
- [License](#license)

---

## Features

| Feature | Description |
|---|---|
| **Incident Lifecycle** | Log, update, assign, and resolve incidents with full audit trail |
| **Role-Based Access** | Admin / Engineer / Viewer with enforced permissions |
| **REST API** | Full CRUD via `/api/v1/` endpoints (JSON) |
| **Email Notifications** | SMTP alerts on create, update, and resolve events |
| **Activity Log** | Per-incident history of every field change with timestamp + author |
| **Comments** | Threaded comments per incident for team communication |
| **Filtering & Search** | Filter by status, severity, and full-text search |
| **Severity Tracking** | Critical / High / Medium / Low with visual indicators |
| **Dashboard** | Real-time KPI cards, recent incidents, severity breakdown |
| **Pagination** | Server-side pagination for large incident volumes |
| **Docker Ready** | Single-command deployment with `docker compose up` |

---

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | Python 3.11 + Flask 3.0 |
| Database | SQLite (via SQLAlchemy ORM) |
| Auth | Flask-Login + Werkzeug password hashing |
| Email | Flask-Mail (SMTP / Gmail) |
| Frontend | Bootstrap 5.3, Bootstrap Icons |
| Server | Gunicorn (production WSGI) |
| Container | Docker + Docker Compose |
| Version Control | Git |

---

## Architecture

```
incidenthub/
│
├── run.py                  # WSGI entry point
├── app/
│   ├── __init__.py         # App factory (create_app)
│   ├── models.py           # SQLAlchemy models
│   ├── utils.py            # Email, history logging, seed data
│   └── routes/
│       ├── auth.py         # Login, logout, register, profile
│       ├── dashboard.py    # Dashboard stats
│       ├── incidents.py    # Web UI CRUD routes
│       └── api.py          # REST API (v1) endpoints
├── templates/
│   ├── base.html           # Shared layout + navbar
│   ├── auth/               # Login, register, profile pages
│   ├── dashboard/          # Dashboard page
│   └── incidents/          # List, view, new, edit pages
├── static/
│   ├── css/style.css       # Custom styles
│   └── js/app.js           # Client JS
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
└── .env.example
```

### Data Models

```
User ─┬─< Incident (created_by)
      └─< Incident (assigned_to)
            │
            ├─< Comment
            └─< IncidentHistory
```

---

## Quick Start

### Prerequisites

- Python 3.11+
- pip

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/incidenthub.git
cd incidenthub
```

### 2. Create Virtual Environment

```bash
python -m venv venv
source venv/bin/activate        # Linux/macOS
venv\Scripts\activate           # Windows
```

### 3. Install Dependencies

```bash
pip install -r requirements.txt
```

### 4. Configure Environment

```bash
cp .env.example .env
# Edit .env with your settings (SECRET_KEY, mail credentials)
```

### 5. Run the Application

```bash
python run.py
```

Open **http://localhost:5000** in your browser. Demo data is auto-seeded on first run.

---

## Docker Deployment

### Using Docker Compose (Recommended)

```bash
# Build and start
docker compose up -d --build

# View logs
docker compose logs -f

# Stop
docker compose down
```

App available at **http://localhost:5000**

### Using Docker Directly

```bash
# Build image
docker build -t incidenthub:latest .

# Run container
docker run -d \
  --name incidenthub \
  -p 5000:5000 \
  -e SECRET_KEY=your-secret-key \
  -v incidenthub_data:/app/instance \
  incidenthub:latest
```

---

## REST API Reference

All API endpoints are under `/api/v1/`. Requires session authentication (login via `/login` first).

### Incidents

| Method | Endpoint | Description | Role Required |
|--------|----------|-------------|---------------|
| GET | `/api/v1/incidents` | List all incidents | Any |
| GET | `/api/v1/incidents/{id}` | Get single incident | Any |
| POST | `/api/v1/incidents` | Create incident | Admin/Engineer |
| PUT | `/api/v1/incidents/{id}` | Update incident | Admin/Engineer |
| POST | `/api/v1/incidents/{id}/assign` | Assign incident | Admin/Engineer |
| POST | `/api/v1/incidents/{id}/resolve` | Resolve incident | Admin/Engineer |
| DELETE | `/api/v1/incidents/{id}` | Delete incident | Admin only |

### Other Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/stats` | Incident statistics |
| GET | `/api/v1/users` | List users (Admin only) |

### Example: Create Incident

```bash
curl -X POST http://localhost:5000/api/v1/incidents \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Database replication lag detected",
    "description": "Read replica is 45 seconds behind primary.",
    "severity": "high",
    "category": "Database",
    "affected_service": "PostgreSQL Replica"
  }'
```

### Example: Get Stats

```bash
curl http://localhost:5000/api/v1/stats
```

Response:
```json
{
  "total": 7,
  "open": 3,
  "in_progress": 2,
  "resolved": 1,
  "closed": 1,
  "critical": 1,
  "high": 2
}
```

### Example: Resolve Incident

```bash
curl -X POST http://localhost:5000/api/v1/incidents/1/resolve
```

---

## Role-Based Access Control

| Action | Admin | Engineer | Viewer |
|--------|:-----:|:--------:|:------:|
| View incidents | ✅ | ✅ | ✅ |
| Create incident | ✅ | ✅ | ❌ |
| Edit incident | ✅ | ✅ | ❌ |
| Assign incident | ✅ | ✅ | ❌ |
| Resolve incident | ✅ | ✅ | ❌ |
| Delete incident | ✅ | ❌ | ❌ |
| Access REST API | ✅ | ✅ | ✅ (read) |
| Manage users | ✅ | ❌ | ❌ |
| Add comments | ✅ | ✅ | ✅ |

---

## Email Notifications

IncidentHub sends automated SMTP email notifications when:

- **New incident created** — Notifies creator, assignee, and all admins
- **Incident updated** — Notifies assignee and admins
- **Incident resolved** — Notifies creator and assignee

### Configure Gmail SMTP

```env
MAIL_SERVER=smtp.gmail.com
MAIL_PORT=587
MAIL_USERNAME=your-email@gmail.com
MAIL_PASSWORD=your-google-app-password
```

> **Note:** Enable 2FA on Gmail and use an [App Password](https://support.google.com/accounts/answer/185833).

Email is **optional** — the app works fully without it. Errors are logged but do not interrupt the workflow.

---

## Demo Credentials

| Role | Username | Password |
|------|----------|----------|
| Admin | `admin` | `Admin@123` |
| Engineer | `john_doe` | `Engineer@123` |
| Engineer | `jane_smith` | `Engineer@123` |
| Viewer | `viewer` | `Viewer@123` |

---

## Sample Incidents

The following incidents are auto-seeded on first launch:

1. **[CRITICAL]** Production Database Connection Pool Exhausted
2. **[HIGH]** API Gateway Latency Spike (P99 > 5s) — In Progress
3. **[MEDIUM]** SSL Certificate Expiry Warning — Open
4. **[HIGH]** Kubernetes Pod CrashLoopBackOff — Resolved
5. **[MEDIUM]** Disk Usage > 90% on Log Server — In Progress
6. **[LOW]** UI Bug - Pagination on Reports Page — Open
7. **[MEDIUM]** Redis Cache Miss Rate Elevated — Closed

---

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SECRET_KEY` | `dev-secret-key` | Flask session secret (change in production!) |
| `DATABASE_URL` | `sqlite:///incidents.db` | SQLAlchemy DB URI |
| `MAIL_SERVER` | `smtp.gmail.com` | SMTP server |
| `MAIL_PORT` | `587` | SMTP port |
| `MAIL_USERNAME` | *(empty)* | SMTP login |
| `MAIL_PASSWORD` | *(empty)* | SMTP password |

---

## Project Structure

```
incidenthub/
├── app/
│   ├── __init__.py          # App factory with extensions
│   ├── models.py            # User, Incident, Comment, IncidentHistory
│   ├── utils.py             # send_notification(), log_history(), seed_demo_data()
│   └── routes/
│       ├── __init__.py
│       ├── auth.py          # /login, /logout, /register, /profile
│       ├── dashboard.py     # / and /dashboard
│       ├── incidents.py     # /incidents/* (web views)
│       └── api.py           # /api/v1/* (REST API)
├── templates/
│   ├── base.html
│   ├── auth/
│   │   ├── login.html
│   │   ├── register.html
│   │   └── profile.html
│   ├── dashboard/
│   │   └── index.html
│   └── incidents/
│       ├── list.html
│       ├── view.html
│       ├── new.html
│       └── edit.html
├── static/
│   ├── css/style.css
│   └── js/app.js
├── run.py
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
├── .env.example
└── .gitignore
```

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit changes: `git commit -m 'Add my feature'`
4. Push to the branch: `git push origin feature/my-feature`
5. Open a Pull Request

---

## License

This project is licensed under the **MIT License**. See [LICENSE](LICENSE) for details.

---

<p align="center">Built with ❤️ using Flask · Bootstrap · SQLite · Docker</p>
