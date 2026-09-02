package zone

import "testing"

const domain = "berne.5gc.3gppnetwork.org"

func TestExpandNumbersFromOne(t *testing.T) {
	names := Expand(domain, 3, 2)

	wantPositive := []string{
		"chaos-test-1-berne.5gc.3gppnetwork.org",
		"chaos-test-2-berne.5gc.3gppnetwork.org",
		"chaos-test-3-berne.5gc.3gppnetwork.org",
	}

	wantNegative := []string{
		"chaos-test-absent-1-berne.5gc.3gppnetwork.org",
		"chaos-test-absent-2-berne.5gc.3gppnetwork.org",
	}

	assertEqual(t, "positive", names.Positive, wantPositive)
	assertEqual(t, "negative", names.Negative, wantNegative)
	assertEqual(t, "all", names.All(), append(wantPositive, wantNegative...))
}

func TestExpandWithoutNegatives(t *testing.T) {
	names := Expand(domain, 2, 0)

	if len(names.Negative) != 0 {
		t.Fatalf("expected no negative names, got %v", names.Negative)
	}

	if len(names.All()) != 2 {
		t.Fatalf("expected 2 names in total, got %v", names.All())
	}
}

func TestOwnsRequiresPrefixAndDomain(t *testing.T) {
	cases := map[string]bool{
		"chaos-test-1-berne.5gc.3gppnetwork.org":        true,
		"chaos-test-absent-1-berne.5gc.3gppnetwork.org": true,
		// Another cluster's records share the prefix but not the domain.
		"chaos-test-1-zurich.5gc.3gppnetwork.org": false,
		// Records owned by something else must never be deleted.
		"berne-1.5gc.3gppnetwork.org":      false,
		"my-app.berne.5gc.3gppnetwork.org": false,
	}

	for name, want := range cases {
		if got := Owns(name, domain); got != want {
			t.Errorf("Owns(%q) = %v, want %v", name, got, want)
		}
	}
}

func assertEqual(t *testing.T, label string, got, want []string) {
	t.Helper()

	if len(got) != len(want) {
		t.Fatalf("%s: got %v, want %v", label, got, want)
	}

	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("%s[%d]: got %q, want %q", label, i, got[i], want[i])
		}
	}
}
