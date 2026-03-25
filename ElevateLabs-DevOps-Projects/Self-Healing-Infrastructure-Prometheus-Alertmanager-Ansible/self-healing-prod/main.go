/*
Self-Healing Infrastructure - Kubernetes Operator (Go)
=====================================================
This operator watches for ServiceHealth custom resources and automatically
heals services that fall below their health thresholds.

Architecture:
  - Custom Resource Definition: ServiceHealth
  - Controller: ServiceHealthReconciler
  - Reconciliation loop: detect → evaluate → heal → report
*/

package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"

	selfhealingv1alpha1 "github.com/company/self-healing-operator/api/v1alpha1"
)

var (
	scheme   = runtime.NewScheme()
	setupLog = ctrl.Log.WithName("setup")
)

func init() {
	utilruntime.Must(clientgoscheme.AddToScheme(scheme))
	utilruntime.Must(selfhealingv1alpha1.AddToScheme(scheme))
}

func main() {
	var metricsAddr string
	var enableLeaderElection bool
	var probeAddr string

	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080", "Metrics endpoint address")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "Health probe bind address")
	flag.BoolVar(&enableLeaderElection, "leader-elect", false, "Enable leader election")
	opts := zap.Options{Development: true}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()

	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))

	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme:                 scheme,
		MetricsBindAddress:     metricsAddr,
		Port:                   9443,
		HealthProbeBindAddress: probeAddr,
		LeaderElection:         enableLeaderElection,
		LeaderElectionID:       "self-healing-operator.company.io",
	})
	if err != nil {
		setupLog.Error(err, "unable to start manager")
		os.Exit(1)
	}

	if err = (&ServiceHealthReconciler{
		Client: mgr.GetClient(),
		Scheme: mgr.GetScheme(),
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "unable to create controller", "controller", "ServiceHealth")
		os.Exit(1)
	}

	setupLog.Info("starting manager")
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLog.Error(err, "problem running manager")
		os.Exit(1)
	}
}

// ─── ServiceHealthReconciler ──────────────────────────────────────────────────

// ServiceHealthReconciler reconciles a ServiceHealth object
type ServiceHealthReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// Reconcile is the main reconciliation loop
// +kubebuilder:rbac:groups=selfhealing.company.io,resources=servicehealths,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=selfhealing.company.io,resources=servicehealths/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups="",resources=pods,verbs=get;list;watch;delete
// +kubebuilder:rbac:groups="",resources=events,verbs=create;patch
func (r *ServiceHealthReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	// ── Fetch the ServiceHealth resource ─────────────────────────────────────
	var serviceHealth selfhealingv1alpha1.ServiceHealth
	if err := r.Get(ctx, req.NamespacedName, &serviceHealth); err != nil {
		if errors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	logger.Info("Reconciling ServiceHealth",
		"name", serviceHealth.Name,
		"namespace", serviceHealth.Namespace,
		"target", serviceHealth.Spec.TargetDeployment)

	// ── Fetch the target Deployment ──────────────────────────────────────────
	var deployment appsv1.Deployment
	deploymentKey := types.NamespacedName{
		Name:      serviceHealth.Spec.TargetDeployment,
		Namespace: serviceHealth.Namespace,
	}

	if err := r.Get(ctx, deploymentKey, &deployment); err != nil {
		if errors.IsNotFound(err) {
			logger.Info("Target deployment not found", "deployment", serviceHealth.Spec.TargetDeployment)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		return ctrl.Result{}, err
	}

	// ── Evaluate health ───────────────────────────────────────────────────────
	healthStatus := r.evaluateHealth(ctx, &deployment, &serviceHealth)
	logger.Info("Health evaluation", "status", healthStatus.State, "availableReplicas", healthStatus.AvailableReplicas)

	// ── Take healing action if needed ─────────────────────────────────────────
	if healthStatus.State == "Unhealthy" {
		if err := r.healService(ctx, &deployment, &serviceHealth, healthStatus); err != nil {
			logger.Error(err, "Failed to heal service")
			r.updateStatus(ctx, &serviceHealth, "Healing", healthStatus, err.Error())
			return ctrl.Result{RequeueAfter: 30 * time.Second}, err
		}
		r.updateStatus(ctx, &serviceHealth, "Healing", healthStatus, "")
		return ctrl.Result{RequeueAfter: 15 * time.Second}, nil
	}

	// ── Update status ─────────────────────────────────────────────────────────
	r.updateStatus(ctx, &serviceHealth, healthStatus.State, healthStatus, "")

	// Re-check after configured interval
	return ctrl.Result{RequeueAfter: time.Duration(serviceHealth.Spec.CheckIntervalSeconds) * time.Second}, nil
}

// ── HealthStatus represents the current health evaluation result ──────────────
type HealthStatus struct {
	State             string
	AvailableReplicas int32
	DesiredReplicas   int32
	Message           string
	CrashLoopPods     []string
}

// evaluateHealth determines the health of the target deployment
func (r *ServiceHealthReconciler) evaluateHealth(
	ctx context.Context,
	deployment *appsv1.Deployment,
	sh *selfhealingv1alpha1.ServiceHealth,
) HealthStatus {

	desired   := *deployment.Spec.Replicas
	available := deployment.Status.AvailableReplicas

	status := HealthStatus{
		DesiredReplicas:   desired,
		AvailableReplicas: available,
	}

	// Check minimum availability threshold
	minThreshold := sh.Spec.MinAvailablePercent
	if minThreshold == 0 {
		minThreshold = 50
	}
	availablePercent := float64(available) / float64(desired) * 100
	if availablePercent < float64(minThreshold) {
		status.State = "Unhealthy"
		status.Message = fmt.Sprintf("Only %.0f%% replicas available (threshold: %d%%)",
			availablePercent, minThreshold)
		return status
	}

	// Check for crash-looping pods
	podList := &corev1.PodList{}
	if err := r.List(ctx, podList,
		client.InNamespace(deployment.Namespace),
		client.MatchingLabels(deployment.Spec.Selector.MatchLabels)); err == nil {

		for _, pod := range podList.Items {
			for _, cs := range pod.Status.ContainerStatuses {
				if cs.RestartCount > sh.Spec.MaxRestartCount {
					status.CrashLoopPods = append(status.CrashLoopPods, pod.Name)
				}
			}
		}
	}

	if len(status.CrashLoopPods) > 0 {
		status.State = "Degraded"
		status.Message = fmt.Sprintf("CrashLooping pods: %v", status.CrashLoopPods)
		return status
	}

	status.State = "Healthy"
	return status
}

// healService performs automated recovery actions
func (r *ServiceHealthReconciler) healService(
	ctx context.Context,
	deployment *appsv1.Deployment,
	sh *selfhealingv1alpha1.ServiceHealth,
	status HealthStatus,
) error {
	logger := log.FromContext(ctx)
	logger.Info("Initiating auto-heal", "deployment", deployment.Name, "reason", status.Message)

	// Strategy 1: Restart CrashLooping pods by deletion (K8s will recreate)
	if len(status.CrashLoopPods) > 0 {
		for _, podName := range status.CrashLoopPods {
			pod := &corev1.Pod{}
			if err := r.Get(ctx, types.NamespacedName{Name: podName, Namespace: deployment.Namespace}, pod); err == nil {
				logger.Info("Deleting crash-looping pod", "pod", podName)
				if err := r.Delete(ctx, pod); err != nil {
					logger.Error(err, "Failed to delete pod", "pod", podName)
				}
			}
		}
		return nil
	}

	// Strategy 2: Roll restart the deployment (triggers new pods)
	if status.AvailableReplicas < status.DesiredReplicas {
		logger.Info("Rolling restart to recover unavailable replicas")
		deploymentCopy := deployment.DeepCopy()
		if deploymentCopy.Spec.Template.Annotations == nil {
			deploymentCopy.Spec.Template.Annotations = make(map[string]string)
		}
		deploymentCopy.Spec.Template.Annotations["kubectl.kubernetes.io/restartedAt"] =
			time.Now().Format(time.RFC3339)
		return r.Update(ctx, deploymentCopy)
	}

	return nil
}

// updateStatus updates the ServiceHealth CR status
func (r *ServiceHealthReconciler) updateStatus(
	ctx context.Context,
	sh *selfhealingv1alpha1.ServiceHealth,
	state string,
	health HealthStatus,
	errMsg string,
) {
	shCopy := sh.DeepCopy()
	shCopy.Status.State             = state
	shCopy.Status.AvailableReplicas = health.AvailableReplicas
	shCopy.Status.LastChecked       = metav1.Now()
	shCopy.Status.Message           = health.Message
	if errMsg != "" {
		shCopy.Status.Message = errMsg
	}
	if state == "Healthy" {
		shCopy.Status.LastHealthyTime = metav1.Now()
	}
	_ = r.Status().Update(ctx, shCopy)
}

// SetupWithManager sets up the controller with the Manager
func (r *ServiceHealthReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&selfhealingv1alpha1.ServiceHealth{}).
		Owns(&appsv1.Deployment{}).
		Complete(r)
}
