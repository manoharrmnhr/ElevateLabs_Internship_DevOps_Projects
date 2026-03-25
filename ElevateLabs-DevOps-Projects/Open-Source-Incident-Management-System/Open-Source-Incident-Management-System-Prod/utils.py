from app import db, mail
from app.models import Incident, User, IncidentHistory
from flask_mail import Message
from flask import current_app
import logging

logger = logging.getLogger(__name__)

def send_notification(incident, event_type):
    """Send email notification for incident events."""
    try:
        if not current_app.config.get('MAIL_USERNAME'):
            logger.info(f"Mail not configured. Skipping notification for incident #{incident.id}")
            return
        recipients = []
        if incident.assignee:
            recipients.append(incident.assignee.email)
        if incident.creator and incident.creator.email not in recipients:
            recipients.append(incident.creator.email)
        admins = User.query.filter_by(role='admin').all()
        for admin in admins:
            if admin.email not in recipients:
                recipients.append(admin.email)
        if not recipients:
            return
        subject_map = {
            'created': f'[NEW] Incident #{incident.id}: {incident.title}',
            'updated': f'[UPDATED] Incident #{incident.id}: {incident.title}',
            'resolved': f'[RESOLVED] Incident #{incident.id}: {incident.title}',
        }
        body = f"""
Incident Management System - Notification
==========================================
Event: {event_type.upper()}
Incident ID: #{incident.id}
Title: {incident.title}
Severity: {incident.severity.upper()}
Status: {incident.status.replace('_', ' ').title()}
Category: {incident.category}
Affected Service: {incident.affected_service or 'N/A'}
Assigned To: {incident.assignee.username if incident.assignee else 'Unassigned'}
Created By: {incident.creator.username if incident.creator else 'N/A'}

Description:
{incident.description}

Please log in to view full details.
        """
        msg = Message(
            subject=subject_map.get(event_type, f'Incident #{incident.id} Update'),
            recipients=recipients,
            body=body
        )
        mail.send(msg)
        logger.info(f"Notification sent for incident #{incident.id} to {recipients}")
    except Exception as e:
        logger.error(f"Failed to send notification: {e}")

def log_history(incident_id, user_id, field, old_value, new_value):
    """Log a change to incident history."""
    try:
        entry = IncidentHistory(
            incident_id=incident_id,
            changed_by_id=user_id,
            field_changed=field,
            old_value=str(old_value) if old_value else None,
            new_value=str(new_value) if new_value else None
        )
        db.session.add(entry)
        db.session.flush()
    except Exception as e:
        logger.error(f"Failed to log history: {e}")

def seed_demo_data():
    """Seed demo data if database is empty."""
    if User.query.count() > 0:
        return

    # Create users
    admin = User(username='admin', email='admin@incidents.local', full_name='System Admin', role='admin')
    admin.set_password('Admin@123')

    eng1 = User(username='john_doe', email='john@incidents.local', full_name='John Doe', role='engineer')
    eng1.set_password('Engineer@123')

    eng2 = User(username='jane_smith', email='jane@incidents.local', full_name='Jane Smith', role='engineer')
    eng2.set_password('Engineer@123')

    viewer = User(username='viewer', email='viewer@incidents.local', full_name='View Only User', role='viewer')
    viewer.set_password('Viewer@123')

    db.session.add_all([admin, eng1, eng2, viewer])
    db.session.commit()

    # Create sample incidents
    samples = [
        {
            'title': 'Production Database Connection Pool Exhausted',
            'description': 'The primary PostgreSQL database connection pool is exhausted. Multiple services are failing to obtain connections, causing 500 errors across the platform. Immediate action required.',
            'severity': 'critical', 'status': 'open', 'category': 'Database',
            'affected_service': 'PostgreSQL / API Gateway', 'created_by_id': eng1.id, 'assigned_to_id': eng1.id
        },
        {
            'title': 'API Gateway Latency Spike (P99 > 5s)',
            'description': 'P99 latency on the API Gateway has exceeded 5 seconds for the past 15 minutes. Root cause suspected to be upstream microservice timeouts. Customers are experiencing slow load times.',
            'severity': 'high', 'status': 'in_progress', 'category': 'Performance',
            'affected_service': 'API Gateway', 'created_by_id': admin.id, 'assigned_to_id': eng2.id
        },
        {
            'title': 'SSL Certificate Expiry Warning - cdn.example.com',
            'description': 'SSL certificate for cdn.example.com will expire in 7 days. Renewal process must be initiated to avoid service disruption. Certificate provider: Let\'s Encrypt.',
            'severity': 'medium', 'status': 'open', 'category': 'Security',
            'affected_service': 'CDN / Static Assets', 'created_by_id': admin.id, 'assigned_to_id': eng2.id
        },
        {
            'title': 'Kubernetes Pod CrashLoopBackOff - payments-service',
            'description': 'The payments-service pod in the production Kubernetes cluster is in CrashLoopBackOff state. Initial log analysis shows OOMKilled errors. Resource limits may need adjustment.',
            'severity': 'high', 'status': 'resolved', 'category': 'Infrastructure',
            'affected_service': 'Payments Service / Kubernetes', 'created_by_id': eng2.id, 'assigned_to_id': eng1.id
        },
        {
            'title': 'Disk Usage > 90% on Log Server',
            'description': 'Log aggregation server (log-01.prod) disk usage has exceeded 90%. Old log rotation policy is not working as expected. Services may start failing if logs cannot be written.',
            'severity': 'medium', 'status': 'in_progress', 'category': 'Infrastructure',
            'affected_service': 'Log Aggregation Server', 'created_by_id': eng1.id, 'assigned_to_id': eng2.id
        },
        {
            'title': 'Minor UI Bug - Pagination on Reports Page',
            'description': 'The pagination component on the /reports page incorrectly shows page 0 when there are no results. Should display a friendly empty state message instead.',
            'severity': 'low', 'status': 'open', 'category': 'Application',
            'affected_service': 'Frontend / Reports Module', 'created_by_id': viewer.id, 'assigned_to_id': None
        },
        {
            'title': 'Redis Cache Miss Rate Elevated (>40%)',
            'description': 'Cache miss rate for the Redis session store has elevated above 40%, up from the normal 5%. This is causing additional load on the backend database. Investigating potential key eviction issue.',
            'severity': 'medium', 'status': 'closed', 'category': 'Performance',
            'affected_service': 'Redis Cache', 'created_by_id': eng2.id, 'assigned_to_id': eng1.id
        },
    ]

    from datetime import datetime, timedelta
    import random
    for i, s in enumerate(samples):
        inc = Incident(**s)
        inc.created_at = datetime.utcnow() - timedelta(hours=random.randint(1, 72))
        if s['status'] in ('resolved', 'closed'):
            inc.resolved_at = datetime.utcnow() - timedelta(hours=random.randint(0, 10))
        db.session.add(inc)

    db.session.commit()
    logger.info("Demo data seeded successfully.")
