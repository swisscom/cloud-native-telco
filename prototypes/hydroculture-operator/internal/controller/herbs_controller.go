/*
Copyright 2026.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package controller

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	hydroculturev1 "containerdays.io/hydroculture/api/v1"
)

// HerbsReconciler reconciles a Herbs object
type HerbsReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=hydroculture.containerdays.io,resources=herbs,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=hydroculture.containerdays.io,resources=herbs/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=hydroculture.containerdays.io,resources=herbs/finalizers,verbs=update
// +kubebuilder:rbac:groups=core,resources=configmaps,verbs=get;list;watch
// +kubebuilder:rbac:groups=core,resources=events,verbs=create;patch

// herbsIdealTemperatures maps plant names to their ideal temperatures in Celsius
var herbsIdealTemperatures = map[string]int{
	"basil":   24,
	"lettuce": 20,
	"spinach": 18,
}

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
// TODO(user): Modify the Reconcile function to compare the state specified by
// the Herbs object against the actual cluster state, and then
// perform operations to make the cluster state reflect the state specified by
// the user.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.23.1/pkg/reconcile
func (r *HerbsReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, reconcileErr error) {
	log := logf.FromContext(ctx)

	// Fetch the Herbs instance
	herbs := &hydroculturev1.Herbs{}
	if err := r.Get(ctx, req.NamespacedName, herbs); err != nil {
		if apierrors.IsNotFound(err) {
			log.Info("Herbs resource not found, ignoring since object must be deleted")
			return ctrl.Result{}, nil
		}
		log.Error(err, "Failed to get Herbs resource")
		return ctrl.Result{}, err
	}

	// Use defer to update conditions at the end of reconciliation
	// This ensures conditions are set on every exit path
	defer func() {
		conditionResult, conditionErr := r.updateConditions(ctx, herbs, reconcileErr)
		if conditionErr != nil {
			log.Error(conditionErr, "Failed to update conditions")
			reconcileErr = errors.Join(reconcileErr, conditionErr)
		}

		// Defer can override the requeue interval based on condition state
		if conditionResult.RequeueAfter > 0 {
			result = conditionResult
		}
	}()

	// Get ideal temperature for the specified plant
	idealTemp, exists := herbsIdealTemperatures[herbs.Spec.Plant]
	if !exists {
		// This should not happen due to CRD validation, but handle it gracefully
		err := fmt.Errorf("unknown plant type: %s", herbs.Spec.Plant)
		log.Error(err, "Invalid plant type")
		return ctrl.Result{}, err
	}

	// Get current temperature from ConfigMap
	currentTemp, err := r.getTemperature(ctx, herbs.Namespace)
	if err != nil {
		log.Error(err, "Failed to get temperature from ConfigMap")
		return ctrl.Result{}, err
	}

	// Store temperature in status (defer will update it along with conditions)
	herbs.Status.Temperature = currentTemp

	// Determine action based on temperature comparison
	if currentTemp < idealTemp {
		log.Info("Temperature below ideal, heating needed",
			"plant", herbs.Spec.Plant,
			"current", currentTemp,
			"ideal", idealTemp)
		// Call heater system here (not implemented in this demo)
	} else if currentTemp > idealTemp {
		log.Info("Temperature above ideal, cooling needed",
			"plant", herbs.Spec.Plant,
			"current", currentTemp,
			"ideal", idealTemp)
		// Call cooler system here (not implemented in this demo)
	} else {
		log.Info("Temperature is optimal",
			"plant", herbs.Spec.Plant,
			"temperature", currentTemp)
	}

	return ctrl.Result{}, nil
}

// getTemperature reads the current temperature from a ConfigMap
func (r *HerbsReconciler) getTemperature(ctx context.Context, namespace string) (int, error) {
	log := logf.FromContext(ctx)

	// Fetch the ConfigMap
	configMap := &corev1.ConfigMap{}
	err := r.Get(ctx, types.NamespacedName{Name: "temperature", Namespace: namespace}, configMap)
	if err != nil {
		log.Error(err, "Failed to get temperature ConfigMap")
		return 0, err
	}

	// Read temperature value from ConfigMap
	tempStr, exists := configMap.Data["value"]
	if !exists {
		return 0, fmt.Errorf("temperature value not found in ConfigMap")
	}

	// Convert string to int
	temp, err := strconv.Atoi(tempStr)
	if err != nil {
		return 0, fmt.Errorf("invalid temperature value: %w", err)
	}

	log.Info("Read temperature from ConfigMap", "temperature", temp)
	return temp, nil
}

// updateConditions updates status conditions based on temperature state and errors
// Called from defer to ensure conditions are always updated
// Returns ctrl.Result with requeue interval when temperature adjustment is needed
func (r *HerbsReconciler) updateConditions(ctx context.Context, herbs *hydroculturev1.Herbs, reconcileErr error) (ctrl.Result, error) {
	log := logf.FromContext(ctx)

	// Determine conditions based on errors or temperature state
	var tempCondition, readyCondition metav1.Condition
	var result ctrl.Result

	if reconcileErr != nil {
		// Sanitize error - remove stack traces for user-friendly messages
		sanitizedErr := fmt.Errorf("%v", reconcileErr)

		// Error occurred during reconciliation - use predefined error conditions
		tempCondition = hydroculturev1.ConditionTempReadyUnknown
		// Override message to include actual error
		tempCondition.Message = fmt.Sprintf("Error: %v", sanitizedErr)
		readyCondition = hydroculturev1.ConditionReadyError
		// Retry after 5 seconds on error
		result = ctrl.Result{RequeueAfter: 5 * time.Second}
	} else {
		// Check if temperature matches ideal
		idealTemp := herbsIdealTemperatures[herbs.Spec.Plant]

		if herbs.Status.Temperature == idealTemp {
			// Temperature matches - set conditions to True
			tempCondition = hydroculturev1.ConditionTempReadyTrue
			readyCondition = hydroculturev1.ConditionReadyTrue
			log.V(1).Info("Temperature is optimal",
				"plant", herbs.Spec.Plant,
				"temperature", herbs.Status.Temperature)
			// Requeue in 10 seconds to check temperature again
			result = ctrl.Result{RequeueAfter: 10 * time.Second}
		} else {
			// Temperature needs adjustment - set conditions to False
			tempCondition = hydroculturev1.ConditionTempReadyFalse
			readyCondition = hydroculturev1.ConditionReadyFalse
			log.V(1).Info("Temperature adjustment in progress",
				"plant", herbs.Spec.Plant,
				"current", herbs.Status.Temperature,
				"ideal", idealTemp)
			// Requeue after 1 second to check again
			result = ctrl.Result{RequeueAfter: time.Second}
		}
	}

	// Set ObservedGeneration (meta.SetStatusCondition handles LastTransitionTime)
	tempCondition.ObservedGeneration = herbs.Generation
	readyCondition.ObservedGeneration = herbs.Generation

	// meta.SetStatusCondition only updates LastTransitionTime if status changed
	meta.SetStatusCondition(&herbs.Status.Conditions, tempCondition)
	meta.SetStatusCondition(&herbs.Status.Conditions, readyCondition)

	if err := r.Status().Update(ctx, herbs); err != nil {
		log.Error(err, "Failed to update Herbs status")
		return ctrl.Result{}, err
	}

	return result, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *HerbsReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&hydroculturev1.Herbs{}).
		Named("herbs").
		Complete(r)
}
