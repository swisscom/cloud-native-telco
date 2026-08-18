package intent_test

import (
	"testing"

	"github.com/taadage2/dns-traffic-generator/internal/intent"
)

func TestSeedSeparatesRotatableFromNXDOMAIN(t *testing.T) {
	store := intent.New()
	store.Seed("a.example.org", "11.1.1.1")
	store.Seed("missing.example.org", intent.NXDOMAIN)

	rotatable := store.Rotatable()
	if len(rotatable) != 1 || rotatable[0] != "a.example.org" {
		t.Fatalf("expected only the record-backed host to be rotatable, got %v", rotatable)
	}

	address, tracked := store.Get("missing.example.org")
	if !tracked {
		t.Fatal("NXDOMAIN host should still be tracked")
	}

	if address != intent.NXDOMAIN {
		t.Fatalf("expected NXDOMAIN intent, got %q", address)
	}
}

func TestGetReportsUntrackedHosts(t *testing.T) {
	store := intent.New()

	if _, tracked := store.Get("unknown.example.org"); tracked {
		t.Fatal("unseeded host should not be tracked")
	}
}

func TestSetOverwritesIntent(t *testing.T) {
	store := intent.New()
	store.Seed("a.example.org", "11.1.1.1")
	store.Set("a.example.org", "11.1.1.200")

	address, _ := store.Get("a.example.org")
	if address != "11.1.1.200" {
		t.Fatalf("expected updated intent, got %q", address)
	}

	if len(store.Rotatable()) != 1 {
		t.Fatalf("Set must not change the rotatable set: %v", store.Rotatable())
	}
}
