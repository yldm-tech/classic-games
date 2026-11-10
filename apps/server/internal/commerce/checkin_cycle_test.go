package commerce

import (
	"testing"
	"time"
)

// The check-in ladder is a repeating cycle, not a staircase that stops at its top rung. Clamping the index to the last
// reward paid the most valuable tier every day from day 8 onward, minting unbounded points from one button, and it also
// pushed the reported streak past the end of the reward array the client indexes with.
func TestCheckinRewardCycleRepeats(t *testing.T) {
	svc, err := NewService()
	if err != nil {
		t.Fatal(err)
	}
	rewards := svc.welfare.Checkin.Rewards
	if len(rewards) == 0 {
		t.Fatal("no reward ladder seeded")
	}

	// Rewind the recorded day after each check-in so the next one counts as consecutive.
	backdate := func() {
		svc.mu.Lock()
		defer svc.mu.Unlock()
		st, stateErr := svc.stateLocked("u")
		if stateErr != nil {
			t.Fatal(stateErr)
		}
		st.LastCheckinDay = time.Now().UTC().AddDate(0, 0, -1).Format("2006-01-02")
	}

	days := len(rewards) * 2
	total := 0
	for day := 0; day < days; day++ {
		_, reward, checkinErr := svc.Checkin("u")
		if checkinErr != nil {
			t.Fatalf("day %d: %v", day+1, checkinErr)
		}
		want := rewards[day%len(rewards)]
		if reward != want {
			t.Fatalf("day %d paid %d, want %d — the ladder must restart at the first rung after a full cycle", day+1, reward, want)
		}
		total += reward
		if position := svc.WelfareFor("u", "zh").Checkin.Streak; position < 0 || position >= len(rewards) {
			t.Fatalf("day %d reported streak %d, outside the %d-rung reward cycle the client indexes with", day+1, position, len(rewards))
		}
		backdate()
	}

	cycle := 0
	for _, r := range rewards {
		cycle += r
	}
	if total != cycle*2 {
		t.Fatalf("two full cycles paid %d, want %d", total, cycle*2)
	}
}
