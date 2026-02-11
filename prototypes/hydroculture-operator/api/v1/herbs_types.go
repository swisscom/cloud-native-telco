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

package v1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// HerbsSpec defines the desired state of Herbs
type HerbsSpec struct {
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "make" to regenerate code after modifying this file
	// The following markers will use OpenAPI v3 schema to validate the value
	// More info: https://book.kubebuilder.io/reference/markers/crd-validation.html

	// Check that its either basil, lettuce, or spinach
	// +kubebuilder:validation:Enum=basil;lettuce;spinach
	// +kubebuilder:validation:Required
	Plant string `json:"plant,omitempty"`
}

// HerbsStatus defines the observed state of Herbs.
type HerbsStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	// For Kubernetes API conventions, see:
	// https://github.com/kubernetes/community/blob/master/contributors/devel/sig-architecture/api-conventions.md#typical-status-properties

	// temperature represents the current temperature reading from the sensor system
	// +optional
	Temperature int `json:"temperature,omitempty"`

	// conditions represent the current state of the Herbs resource.
	// Each condition has a unique type and reflects the status of a specific aspect of the resource.
	//
	// Standard condition types include:
	// - "Available": the resource is fully functional
	// - "Progressing": the resource is being created or updated
	// - "Degraded": the resource failed to reach or maintain its desired state
	//
	// The status of each condition is one of True, False, or Unknown.
	// +listType=map
	// +listMapKey=type
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="TempReady",type=string,JSONPath=`.status.conditions[?(@.type=="TempReady")].status`
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=`.status.conditions[?(@.type=="Ready")].status`

// Herbs is the Schema for the herbs API
type Herbs struct {
	metav1.TypeMeta `json:",inline"`

	// metadata is a standard object metadata
	// +optional
	metav1.ObjectMeta `json:"metadata,omitzero"`

	// spec defines the desired state of Herbs
	// +required
	Spec HerbsSpec `json:"spec"`

	// status defines the observed state of Herbs
	// +optional
	Status HerbsStatus `json:"status,omitzero"`
}

// +kubebuilder:object:root=true

// HerbsList contains a list of Herbs
type HerbsList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitzero"`
	Items           []Herbs `json:"items"`
}

func init() {
	SchemeBuilder.Register(&Herbs{}, &HerbsList{})
}

var ConditionTempReadyTrue = metav1.Condition{
	Type:    "TempReady",
	Status:  metav1.ConditionTrue,
	Reason:  "TemperatureMatches",
	Message: "Temperature matches desired state",
}

var ConditionTempReadyFalse = metav1.Condition{
	Type:    "TempReady",
	Status:  metav1.ConditionFalse,
	Reason:  "TemperatureMismatch",
	Message: "Temperature does not match desired state",
}

var ConditionReadyTrue = metav1.Condition{
	Type:    "Ready",
	Status:  metav1.ConditionTrue,
	Reason:  "AllConditionsReady",
	Message: "All conditions are ready",
}

var ConditionReadyFalse = metav1.Condition{
	Type:    "Ready",
	Status:  metav1.ConditionFalse,
	Reason:  "NotReady",
	Message: "Not all conditions are ready",
}

var ConditionTempReadyUnknown = metav1.Condition{
	Type:    "TempReady",
	Status:  metav1.ConditionUnknown,
	Reason:  "ReconciliationError",
	Message: "Cannot read temperature due to error",
}

var ConditionReadyError = metav1.Condition{
	Type:    "Ready",
	Status:  metav1.ConditionFalse,
	Reason:  "ReconciliationError",
	Message: "Cannot determine readiness due to reconciliation error",
}
