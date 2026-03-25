from flask import Blueprint, request, jsonify
from flask_login import login_required, current_user
from app import db
from app.models import Incident, User, Comment
from app.utils import send_notification, log_history
from datetime import datetime
from functools import wraps

api_bp = Blueprint('api', __name__)

def api_login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not current_user.is_authenticated:
            return jsonify({'error': 'Authentication required'}), 401
        return f(*args, **kwargs)
    return decorated

def require_role(*roles):
    def decorator(f):
        @wraps(f)
        def decorated(*args, **kwargs):
            if current_user.role not in roles:
                return jsonify({'error': 'Insufficient permissions'}), 403
            return f(*args, **kwargs)
        return decorated
    return decorator

@api_bp.route('/incidents', methods=['GET'])
@api_login_required
def get_incidents():
    status = request.args.get('status')
    severity = request.args.get('severity')
    query = Incident.query
    if status:
        query = query.filter_by(status=status)
    if severity:
        query = query.filter_by(severity=severity)
    incidents = query.order_by(Incident.created_at.desc()).all()
    return jsonify({'incidents': [i.to_dict() for i in incidents], 'total': len(incidents)})

@api_bp.route('/incidents/<int:id>', methods=['GET'])
@api_login_required
def get_incident(id):
    incident = Incident.query.get_or_404(id)
    return jsonify(incident.to_dict())

@api_bp.route('/incidents', methods=['POST'])
@api_login_required
@require_role('admin', 'engineer')
def create_incident():
    data = request.get_json()
    if not data or not data.get('title') or not data.get('description'):
        return jsonify({'error': 'title and description are required'}), 400
    incident = Incident(
        title=data['title'],
        description=data['description'],
        severity=data.get('severity', 'medium'),
        category=data.get('category', 'General'),
        affected_service=data.get('affected_service', ''),
        created_by_id=current_user.id,
        assigned_to_id=data.get('assigned_to_id'),
        status='open'
    )
    db.session.add(incident)
    db.session.commit()
    log_history(incident.id, current_user.id, 'status', None, 'open')
    send_notification(incident, 'created')
    return jsonify(incident.to_dict()), 201

@api_bp.route('/incidents/<int:id>', methods=['PUT'])
@api_login_required
@require_role('admin', 'engineer')
def update_incident(id):
    incident = Incident.query.get_or_404(id)
    data = request.get_json()
    old_status = incident.status

    for field in ['title', 'description', 'severity', 'status', 'category', 'affected_service']:
        if field in data:
            old_val = getattr(incident, field)
            setattr(incident, field, data[field])
            if old_val != data[field]:
                log_history(incident.id, current_user.id, field, str(old_val), str(data[field]))

    if 'assigned_to_id' in data:
        incident.assigned_to_id = data['assigned_to_id']

    incident.updated_at = datetime.utcnow()
    if incident.status in ('resolved', 'closed') and not incident.resolved_at:
        incident.resolved_at = datetime.utcnow()

    db.session.commit()
    send_notification(incident, 'updated')
    return jsonify(incident.to_dict())

@api_bp.route('/incidents/<int:id>/assign', methods=['POST'])
@api_login_required
@require_role('admin', 'engineer')
def assign_incident(id):
    incident = Incident.query.get_or_404(id)
    data = request.get_json()
    assignee_id = data.get('assigned_to_id')
    user = User.query.get(assignee_id) if assignee_id else None
    old_assigned = incident.assigned_to_id
    incident.assigned_to_id = assignee_id
    incident.updated_at = datetime.utcnow()
    log_history(incident.id, current_user.id, 'assigned_to', str(old_assigned), str(assignee_id))
    db.session.commit()
    return jsonify({'message': f'Assigned to {user.username if user else "nobody"}', 'incident': incident.to_dict()})

@api_bp.route('/incidents/<int:id>/resolve', methods=['POST'])
@api_login_required
@require_role('admin', 'engineer')
def resolve_incident(id):
    incident = Incident.query.get_or_404(id)
    old_status = incident.status
    incident.status = 'resolved'
    incident.resolved_at = datetime.utcnow()
    incident.updated_at = datetime.utcnow()
    log_history(incident.id, current_user.id, 'status', old_status, 'resolved')
    db.session.commit()
    send_notification(incident, 'resolved')
    return jsonify({'message': 'Incident resolved', 'incident': incident.to_dict()})

@api_bp.route('/incidents/<int:id>', methods=['DELETE'])
@api_login_required
@require_role('admin')
def delete_incident(id):
    incident = Incident.query.get_or_404(id)
    db.session.delete(incident)
    db.session.commit()
    return jsonify({'message': f'Incident #{id} deleted'})

@api_bp.route('/stats', methods=['GET'])
@api_login_required
def get_stats():
    return jsonify({
        'total': Incident.query.count(),
        'open': Incident.query.filter_by(status='open').count(),
        'in_progress': Incident.query.filter_by(status='in_progress').count(),
        'resolved': Incident.query.filter_by(status='resolved').count(),
        'closed': Incident.query.filter_by(status='closed').count(),
        'critical': Incident.query.filter_by(severity='critical').count(),
        'high': Incident.query.filter_by(severity='high').count(),
    })

@api_bp.route('/users', methods=['GET'])
@api_login_required
@require_role('admin')
def get_users():
    users = User.query.all()
    return jsonify({'users': [u.to_dict() for u in users]})
