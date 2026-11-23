"""Source-level regression checks for the standalone Roblox Luau script.

These tests guard reviewed safety/correctness invariants without requiring Roblox.
They are intentionally source-contract tests, not a substitute for an authorized runtime test.
"""
from pathlib import Path
import unittest


SOURCE = (Path(__file__).resolve().parents[1] / "main.lua").read_text(encoding="utf-8")


def section(start: str, end: str) -> str:
    start_at = SOURCE.index(start)
    end_at = SOURCE.index(end, start_at) if end else len(SOURCE)
    return SOURCE[start_at:end_at]


class ReviewRegressionTests(unittest.TestCase):
    def test_safe_preserves_false_results(self) -> None:
        safe = section("local function safe(", "local globalEnv")
        self.assertIn("if ok then return result end", safe)
        self.assertNotIn("return ok and result or nil", safe)

    def test_legacy_load_guard_can_recover_without_a_live_ui(self) -> None:
        guard = section("local globalEnv", "-- Primitives")
        self.assertIn("existingGuard == true", guard)
        self.assertIn("hasGui ~= false then return end", guard)
        self.assertIn("loadedMarker = {active=true", guard)

    def test_executor_identification_is_protected(self) -> None:
        detect = section("local function detectExecutor()", "Executor = detectExecutor()")
        self.assertIn("pcall(identifyexecutor)", detect)

    def test_compat_file_probe_uses_a_reserved_temporary_path(self) -> None:
        file_test = section('{"file I/O",', '{"decompile",')
        self.assertIn('type(isfile) ~= "function"', file_test)
        self.assertIn('ACProbe_v%d_compat_', file_test)
        self.assertIn('exists == false', file_test)
        self.assertIn('type(delfile) == "function"', file_test)
        self.assertNotIn('"ACProbe_v7.tmp"', file_test)

    def test_live_hook_is_opt_in_and_pause_detaches(self) -> None:
        startup = section("-- Kickoff", "")
        self.assertNotIn("installProfilerHook()", startup)
        live = section("local function startLive()", "runBtn.MouseButton1Click")
        self.assertIn("installProfilerHook()", live)
        stop_live = section("local function stopLive()", "runBtn.MouseButton1Click")
        self.assertIn("detachProfilerHook()", stop_live)
        self.assertIn("Profiler.detachFailed", live)

    def test_probe_cancels_and_always_attempts_conditional_cleanup(self) -> None:
        probe = section("-- AutoProbe (explicitly confirmed", "-- Runner + Live + Buttons")
        self.assertIn("AutoProbe.cancelRequested", probe)
        self.assertIn("pcall(teardown)", probe)
        self.assertIn("current ~= probeValue", probe)
        self.assertIn("player.Character ~= char", probe)
        self.assertIn("remote calls during observation window (not attributed)", probe)
        self.assertNotIn("riskyEnabled", probe)
        self.assertNotIn("Noclip", probe)

    def test_close_waits_for_cleanup_before_detaching(self) -> None:
        close = section("closeBtn.MouseButton1Click:Connect", "-- Kickoff")
        self.assertIn("AutoProbe.cancelRequested = true", close)
        self.assertIn("while AutoProbe.running or running or startupRunning", close)
        self.assertIn("local detached = stopLive()", close)
        self.assertIn("clearLoadedGuard()", close)

    def test_outcomes_are_not_scored_as_causal_evidence(self) -> None:
        outcomes = section("function Outcomes.startMonitor", "-- Behavioral profiler")
        self.assertIn("not shutdownRequested", outcomes)
        self.assertNotIn('push("remotes"', outcomes)

    def test_wipe_clears_session_state_and_invalidates_pending_outcomes(self) -> None:
        wipe = section("wipeBtn.MouseButton1Click:Connect", "local closePending")
        self.assertIn("Outcomes.generation = Outcomes.generation + 1", wipe)
        self.assertIn("currentSession.findingsByKey = {}", wipe)
        self.assertIn('fileDeleted and "Wiped" or "Memory only"', wipe)

    def test_saved_data_is_schema_checked_and_outcomes_are_restored(self) -> None:
        persist = section("local function persistLoad()", "-- Client-visible changes observed near name-matched calls")
        self.assertIn("data.schema ~= SCHEMA", persist)
        self.assertIn("data.schema ~= LEGACY_SCHEMA", persist)
        self.assertIn("data.placeId ~= game.PlaceId", persist)
        self.assertIn("#content > 2 * 1024 * 1024", persist)
        self.assertIn("loaded.outcomes", persist)
        self.assertIn("table.insert(Outcomes.entries", persist)

    def test_reputation_and_baseline_recompute_from_raw_finding_state(self) -> None:
        classification = section("local function applyFindingState", "local function push(")
        self.assertIn('class == "confirmed_benign"', classification)
        self.assertIn('weight, level = 0, "ok"', classification)
        self.assertIn("e.rawWeight", classification)
        detections = section("local function renderDetections()", "local function renderProbes()")
        self.assertIn("UserInputService:IsKeyDown", detections)
        self.assertIn("Baseline[key] = not Baseline[key] or nil", detections)
        self.assertIn("saveNow()", detections)
        self.assertIn('Reputation.Get(key) == "confirmed_benign"', detections)

    def test_fingerprint_confidence_matches_documented_thresholds(self) -> None:
        self.assertIn("Fingerprint.confidence = \"high\"", SOURCE)
        self.assertIn("top.ratio >= 0.8 and top.matched >= 3", SOURCE)
        self.assertIn("top.ratio >= 0.5 and top.matched >= 2", SOURCE)
        self.assertNotIn("fp=fp", SOURCE)


if __name__ == "__main__":
    unittest.main()
