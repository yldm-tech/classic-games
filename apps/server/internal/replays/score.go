package replays

import "math"

const (
	maxSpeedUnits  = 1600.0
	speedSlack     = 48.0
	maxScorePerSec = 8000.0
	scoreSlack     = 600
)

// PhysicalScore validates a client snapshot timeline against speed and
// scoring bounds. It is anti-cheat, not a full authoritative simulator:
// honest traces keep their last-frame score; impossible jumps are rejected.
func PhysicalScore(frames []Frame) (int, bool) {
	if len(frames) < 2 {
		return 0, false
	}
	prev := frames[0]
	for i, frame := range frames {
		if frame.Score < 0 || frame.AtMS < 0 {
			return 0, false
		}
		elapsed := float64(frame.AtMS) / 1000.0
		if frame.Score > int(maxScorePerSec*elapsed)+scoreSlack {
			return 0, false
		}
		if i == 0 {
			continue
		}
		if frame.Score < prev.Score {
			return 0, false
		}
		dt := float64(frame.AtMS-prev.AtMS) / 1000.0
		if dt < 0 {
			return 0, false
		}
		dist := math.Hypot(frame.X-prev.X, frame.Y-prev.Y)
		if dt > 0 && dist > maxSpeedUnits*dt+speedSlack {
			return 0, false
		}
		gain := frame.Score - prev.Score
		if gain > int(maxScorePerSec*dt)+scoreSlack {
			return 0, false
		}
		prev = frame
	}
	return frames[len(frames)-1].Score, true
}
