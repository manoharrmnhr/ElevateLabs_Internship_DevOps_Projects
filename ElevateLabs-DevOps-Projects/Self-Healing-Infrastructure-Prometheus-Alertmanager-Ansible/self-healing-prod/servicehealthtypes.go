/*
Package v1alpha1 contains API types for the Self-Healing Operator.
*/

package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/scheme"
)

// ─── GroupVersion ─────────────────────────────────────────────────────────────
var (
	GroupVersion  = schema.GroupVersion{Group: "selfhealing.company.io", Version: "v1alpha1"}
	SchemeBuilder = &scheme.Builder{GroupVersion: GroupVersion}
	AddToScheme   = SchemeBuilder.AddToScheme
)

func init() {
	SchemeBuilder.Register(&ServiceHealth{}, &ServiceHealthList{})
}

// ─── ServiceHealthSpec ────────────────────────────────────────────────────────

// ServiceHealthSpec defines the desired state of ServiceHealth
type ServiceHealthSpec struct {
	// TargetDeployment is the Deployment to monitor and heal
	// +kubebuilder:validation:Required
	TargetDeployment string `json:"targetDeployment"`

	// CheckIntervalSeconds — how often to evaluate health (default: 30)
	// +kubebuilder:validation:Minimum=10
	// +kubebuilder:default=30
	CheckIntervalSeconds int `json:"checkIntervalSeconds,omitempty"`

	// MinAvailablePercent — minimum % of replicas that must be available (default: 50)
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=100
	// +kubebuilder:default=50
	MinAvailablePercent int `json:"minAvailablePercent,omitempty"`

	// MaxRestartCount — max pod restarts before triggering recovery (default: 5)
	// +kubebuilder:default=5
	MaxRestartCount int32 `json:"maxRestartCount,omitempty"`

	// RecoveryStrategy — healing strategy: RollingRestart | ScaleDown | DeletePod
	// +kubebuilder:validation:Enum=RollingRestart;ScaleDown;DeletePod
	// +kubebuilder:default=RollingRestart
	RecoveryStrategy string `json:"recoveryStrategy,omitempty"`

	// MaxRecoveryAttempts — max auto-recovery attempts before escalating (default: 3)
	// +kubebuilder:default=3
	MaxRecoveryAttempts int `json:"maxRecoveryAttempts,omitempty"`

	// CooldownSeconds — minimum seconds between recovery attempts (default: 120)
	// +kubebuilder:default=120
	CooldownSeconds int `json:"cooldownSeconds,omitempty"`

	// NotificationWebhook — URL to POST recovery events to (optional)
	NotificationWebhook string `json:"notificationWebhook,omitempty"`

	// HealthCheckURL — HTTP URL for external health verification (optional)
	HealthCheckURL string `json:"healthCheckUrl,omitempty"`
}

// ─── ServiceHealthStatus ──────────────────────────────────────────────────────

// ServiceHealthStatus defines the observed state of ServiceHealth
type ServiceHealthStatus struct {
	// State: Healthy | Unhealthy | Degraded | Healing | Unknown
	State string `json:"state,omitempty"`

	// AvailableReplicas is the current number of available replicas
	AvailableReplicas int32 `json:"availableReplicas,omitempty"`

	// LastChecked is when the health was last evaluated
	LastChecked metav1.Time `json:"lastChecked,omitempty"`

	// LastHealthyTime is when the service was last confirmed healthy
	LastHealthyTime metav1.Time `json:"lastHealthyTime,omitempty"`

	// RecoveryAttempts is the number of recovery attempts made
	RecoveryAttempts int `json:"recoveryAttempts,omitempty"`

	// LastRecoveryTime is when the last recovery was triggered
	LastRecoveryTime metav1.Time `json:"lastRecoveryTime,omitempty"`

	// Message provides human-readable status information
	Message string `json:"message,omitempty"`

	// Conditions contains standard K8s condition types
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// ─── ServiceHealth CR ─────────────────────────────────────────────────────────

// ServiceHealth is the Schema for the servicehealths API
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="Target",type=string,JSONPath=`.spec.targetDeployment`
// +kubebuilder:printcolumn:name="State",type=string,JSONPath=`.status.state`
// +kubebuilder:printcolumn:name="Available",type=integer,JSONPath=`.status.availableReplicas`
// +kubebuilder:printcolumn:name="Attempts",type=integer,JSONPath=`.status.recoveryAttempts`
// +kubebuilder:printcolumn:name="Last Checked",type=date,JSONPath=`.status.lastChecked`
type ServiceHealth struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   ServiceHealthSpec   `json:"spec,omitempty"`
	Status ServiceHealthStatus `json:"status,omitempty"`
}

// DeepCopyObject implements runtime.Object
func (s *ServiceHealth) DeepCopyObject() runtime.Object {
	if c := s.DeepCopy(); c != nil {
		return c
	}
	return nil
}

func (s *ServiceHealth) DeepCopy() *ServiceHealth {
	if s == nil {
		return nil
	}
	out := new(ServiceHealth)
	s.DeepCopyInto(out)
	return out
}

func (s *ServiceHealth) DeepCopyInto(out *ServiceHealth) {
	*out = *s
	out.TypeMeta = s.TypeMeta
	s.ObjectMeta.DeepCopyInto(&out.ObjectMeta)
	out.Spec = s.Spec
	s.Status.DeepCopyInto(&out.Status)
}

func (ss *ServiceHealthStatus) DeepCopyInto(out *ServiceHealthStatus) {
	*out = *ss
	out.LastChecked     = ss.LastChecked
	out.LastHealthyTime = ss.LastHealthyTime
	out.LastRecoveryTime = ss.LastRecoveryTime
	if ss.Conditions != nil {
		out.Conditions = make([]metav1.Condition, len(ss.Conditions))
		copy(out.Conditions, ss.Conditions)
	}
}

// ─── ServiceHealthList ────────────────────────────────────────────────────────

// ServiceHealthList contains a list of ServiceHealth
// +kubebuilder:object:root=true
type ServiceHealthList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []ServiceHealth `json:"items"`
}

func (s *ServiceHealthList) DeepCopyObject() runtime.Object {
	out := new(ServiceHealthList)
	*out = *s
	if s.Items != nil {
		out.Items = make([]ServiceHealth, len(s.Items))
		for i := range s.Items {
			s.Items[i].DeepCopyInto(&out.Items[i])
		}
	}
	return out
}
