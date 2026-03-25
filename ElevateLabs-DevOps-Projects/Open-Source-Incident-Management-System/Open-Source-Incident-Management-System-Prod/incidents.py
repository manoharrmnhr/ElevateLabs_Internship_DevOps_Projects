from flask import Blueprint, render_template, redirect, url_for, flash, request, abort
from flask_login import login_required, current_user
from app import db
from app.models import Incident, User, Comment, IncidentHistory
from app.utils import send_notification, log_history
from datetime import datetime

incidents_bp = Blueprint('incidents', __name__, url_prefix='/incidents')

def require_roles(*roles):
    from functools import wraps
    def decorator(f):
        @wraps(f)
        def decorated(*args, **kwargs):
            if current_user.role not in roles:
                flash('You do not have permission to perform this action.', 'danger')
                return redirect(url_for('incidents.list_incidents'))
            return f(*args, **kwargs)
        return decorated
    return decorator

@incidents_bp.route('/')
@login_required
def list_incidents():
    page = request.args.get('page', 1, type=int)
    status = request.args.get('status', '')
    severity = request.args.get('severity', '')
    search = request.args.get('search', '')

    query = Incident.query
    if status:
        query = query.filter_by(status=status)
    if severity:
        query = query.filter_by(severity=severity)
    if search:
        query = query.filter(Incident.title.ilike(f'%{search}%') | Incident.description.ilike(f'%{search}%'))

    incidents = query.order_by(Incident.created_at.desc()).paginate(page=page, per_page=10, error_out=False)
    engineers = User.query.filter(User.role.in_(['admin','engineer'])).all()
    return render_template('incidents/list.html', incidents=incidents, engineers=engineers,
                           status=status, severity=severity, search=search)

@incidents_bp.route('/new', methods=['GET', 'POST'])
@login_required
@require_roles('admin', 'engineer')
def new_incident():
    engineers = User.query.filter(User.role.in_(['admin','engineer'])).all()
    if request.method == 'POST':
        incident = Incident(
            title=request.form['title'],
            description=request.form['description'],
            severity=request.form['severity'],
            category=request.form.get('category', 'General'),
            affected_service=request.form.get('affected_service', ''),
            created_by_id=current_user.id,
            assigned_to_id=request.form.get('assigned_to') or None,
            status='open'
        )
        db.session.add(incident)
        db.session.commit()
        log_history(incident.id, current_user.id, 'status', None, 'open')
        send_notification(incident, 'created')
        flash(f'Incident #{incident.id} created successfully.', 'success')
        return redirect(url_for('incidents.view_incident', id=incident.id))
    return render_template('incidents/new.html', engineers=engineers)

@incidents_bp.route('/<int:id>')
@login_required
def view_incident(id):
    incident = Incident.query.get_or_404(id)
    engineers = User.query.filter(User.role.in_(['admin','engineer'])).all()
    history = IncidentHistory.query.filter_by(incident_id=id).order_by(IncidentHistory.changed_at.desc()).all()
    return render_template('incidents/view.html', incident=incident, engineers=engineers, history=history)

@incidents_bp.route('/<int:id>/edit', methods=['GET', 'POST'])
@login_required
@require_roles('admin', 'engineer')
def edit_incident(id):
    incident = Incident.query.get_or_404(id)
    engineers = User.query.filter(User.role.in_(['admin','engineer'])).all()
    if request.method == 'POST':
        old_status = incident.status
        old_severity = incident.severity
        old_assigned = incident.assigned_to_id

        incident.title = request.form['title']
        incident.description = request.form['description']
        incident.severity = request.form['severity']
        incident.status = request.form['status']
        incident.category = request.form.get('category', 'General')
        incident.affected_service = request.form.get('affected_service', '')
        incident.assigned_to_id = request.form.get('assigned_to') or None
        incident.updated_at = datetime.utcnow()

        if incident.status in ('resolved', 'closed') and not incident.resolved_at:
            incident.resolved_at = datetime.utcnow()

        if old_status != incident.status:
            log_history(incident.id, current_user.id, 'status', old_status, incident.status)
        if old_severity != incident.severity:
            log_history(incident.id, current_user.id, 'severity', old_severity, incident.severity)
        if old_assigned != incident.assigned_to_id:
            log_history(incident.id, current_user.id, 'assigned_to', str(old_assigned), str(incident.assigned_to_id))

        db.session.commit()
        send_notification(incident, 'updated')
        flash('Incident updated successfully.', 'success')
        return redirect(url_for('incidents.view_incident', id=incident.id))
    return render_template('incidents/edit.html', incident=incident, engineers=engineers)

@incidents_bp.route('/<int:id>/comment', methods=['POST'])
@login_required
def add_comment(id):
    incident = Incident.query.get_or_404(id)
    content = request.form.get('content', '').strip()
    if content:
        comment = Comment(content=content, incident_id=id, user_id=current_user.id)
        db.session.add(comment)
        db.session.commit()
        flash('Comment added.', 'success')
    return redirect(url_for('incidents.view_incident', id=id))

@incidents_bp.route('/<int:id>/resolve', methods=['POST'])
@login_required
@require_roles('admin', 'engineer')
def resolve_incident(id):
    incident = Incident.query.get_or_404(id)
    old_status = incident.status
    incident.status = 'resolved'
    incident.resolved_at = datetime.utcnow()
    incident.updated_at = datetime.utcnow()
    log_history(incident.id, current_user.id, 'status', old_status, 'resolved')
    db.session.commit()
    send_notification(incident, 'resolved')
    flash(f'Incident #{id} marked as resolved.', 'success')
    return redirect(url_for('incidents.view_incident', id=id))

@incidents_bp.route('/<int:id>/delete', methods=['POST'])
@login_required
@require_roles('admin')
def delete_incident(id):
    incident = Incident.query.get_or_404(id)
    db.session.delete(incident)
    db.session.commit()
    flash(f'Incident #{id} deleted.', 'warning')
    return redirect(url_for('incidents.list_incidents'))
