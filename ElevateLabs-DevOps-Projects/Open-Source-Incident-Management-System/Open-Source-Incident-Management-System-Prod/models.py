from app import db
from flask_login import UserMixin
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import datetime
import enum

class RoleEnum(str, enum.Enum):
    ADMIN = 'admin'
    ENGINEER = 'engineer'
    VIEWER = 'viewer'

class SeverityEnum(str, enum.Enum):
    CRITICAL = 'critical'
    HIGH = 'high'
    MEDIUM = 'medium'
    LOW = 'low'

class StatusEnum(str, enum.Enum):
    OPEN = 'open'
    IN_PROGRESS = 'in_progress'
    RESOLVED = 'resolved'
    CLOSED = 'closed'

class User(UserMixin, db.Model):
    __tablename__ = 'users'
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    role = db.Column(db.String(20), default=RoleEnum.VIEWER.value, nullable=False)
    full_name = db.Column(db.String(120))
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    is_active = db.Column(db.Boolean, default=True)

    incidents_created = db.relationship('Incident', foreign_keys='Incident.created_by_id', backref='creator', lazy='dynamic')
    incidents_assigned = db.relationship('Incident', foreign_keys='Incident.assigned_to_id', backref='assignee', lazy='dynamic')
    comments = db.relationship('Comment', backref='author', lazy='dynamic')

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

    def to_dict(self):
        return {'id': self.id, 'username': self.username, 'email': self.email,
                'role': self.role, 'full_name': self.full_name}

class Incident(db.Model):
    __tablename__ = 'incidents'
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text, nullable=False)
    severity = db.Column(db.String(20), default=SeverityEnum.MEDIUM.value, nullable=False)
    status = db.Column(db.String(20), default=StatusEnum.OPEN.value, nullable=False)
    category = db.Column(db.String(80), default='General')
    affected_service = db.Column(db.String(120))
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    resolved_at = db.Column(db.DateTime, nullable=True)
    created_by_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    assigned_to_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=True)

    comments = db.relationship('Comment', backref='incident', lazy='dynamic', cascade='all, delete-orphan')
    history = db.relationship('IncidentHistory', backref='incident', lazy='dynamic', cascade='all, delete-orphan')

    def to_dict(self):
        return {
            'id': self.id, 'title': self.title, 'description': self.description,
            'severity': self.severity, 'status': self.status, 'category': self.category,
            'affected_service': self.affected_service,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
            'resolved_at': self.resolved_at.isoformat() if self.resolved_at else None,
            'created_by': self.creator.username if self.creator else None,
            'assigned_to': self.assignee.username if self.assignee else None,
        }

class Comment(db.Model):
    __tablename__ = 'comments'
    id = db.Column(db.Integer, primary_key=True)
    content = db.Column(db.Text, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    incident_id = db.Column(db.Integer, db.ForeignKey('incidents.id'), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)

class IncidentHistory(db.Model):
    __tablename__ = 'incident_history'
    id = db.Column(db.Integer, primary_key=True)
    incident_id = db.Column(db.Integer, db.ForeignKey('incidents.id'), nullable=False)
    changed_by_id = db.Column(db.Integer, db.ForeignKey('users.id'))
    field_changed = db.Column(db.String(80))
    old_value = db.Column(db.String(200))
    new_value = db.Column(db.String(200))
    changed_at = db.Column(db.DateTime, default=datetime.utcnow)
    changed_by = db.relationship('User', foreign_keys=[changed_by_id])
