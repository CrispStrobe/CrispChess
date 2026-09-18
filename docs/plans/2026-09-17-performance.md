# Search and inference performance implementation plan

> **Status (shipped):** §1 baseline, §2 native search lifecycle (§2's web half
> excluded) and §5's statistics helper + reproducible commands are implemented
> and covered by tests. **Not implemented:** §3 (browser worker — web still
> searches on the UI thread), §4 (Maia worker selection — an unwired tuner was
> written and discarded rather than shipped dead), and the measurement runs in
> §2/§4/§6, so no speedup is claimed anywhere.

> **For Hermes:** Use subagent-driven-development for implementation and independent review.

**Goal:** Remove redundant search work, make cancellation effective, keep web search off the UI thread, select Maia worker counts from measurements, and make verification reproducible.

**Architecture:** A persistent platform search transport owns one computation at a time. Native isolates and browser workers stream completed depths from the engine library's existing onDepthComplete callback. Cancellation terminates synchronous work; generation guards prevent late results from mutating state. Maia retains batch-1 semantics while selecting a worker count using measured calibration with conservative fallback.

**Tech Stack:** Flutter/Dart, crisp_chess_engine 0.8.1, package:web, onnx_runtime_dart, existing Flutter test harnesses.

## 1. Establish baseline
- Run flutter analyze --no-pub and flutter test --no-pub --reporter expanded, saving logs outside the repository.
- Inspect engine search callbacks, lifecycle callers, web build scripts, inference experiments and parity tests.
- Preserve baseline measurements before production changes; do not overlap performance comparisons with other tests/builds.

## 2. Search lifecycle tracer bullet
- Add a regression in test/dart_engine_cancellation_test.dart proving stop/dispose/supersession prevents stale computation results and completes promptly.
- Run the regression against existing DartEngine and record expected behavioral failure.
- Replace repeated compute() invocations in lib/engines/dart_engine.dart with a platform search transport, using the dependency's onDepthComplete callback for one iterative-deepening search per request.
- Keep native worker alive after normal completion; kill it on active cancellation and recreate lazily.
- Preserve legal fallback for tiny budgets, repetition history, skill weakening and ready/disposed state behavior.
- Add worker reuse, stream cancellation, invalid-position and lifecycle tests. Run existing DartEngine tests.

## 3. Browser worker tracer bullet
- Implement a compiled Dart web worker with AlphaBetaSearch, no Flutter imports. Exchange structured request/result/error messages and preserve full history.
- Wire web asset compilation into existing web build paths and document it.
- Verify real browser search, cancellation and heartbeat responsiveness; no synchronous UI fallback.
- Compile Flutter web and ensure deployment scripts deliver the worker asset.

## 4. Maia worker tuning tracer bullet
- Test selection/validation/lifecycle behavior before implementation.
- Replace the unconditional four-worker default in lib/engines/maia3_dart/onnx_runtime_backend.dart with measured device-aware selection, explicit override and conservative fallback.
- Compare 1/2/4 workers with identical inputs and warm-up; maintain batch-1 execution and output parity.
- Record available hardware results and mark unavailable device/memory measurements honestly.

## 5. Reproducible checks
- Replace package.json's failing placeholder with Flutter test commands, add documented analysis and bounded performance commands.
- Extend tool/perf with machine-readable cold/warm search latency, percentile/cancellation metrics and browser responsiveness measurements where feasible.
- Add CI correctness gates; avoid brittle timing thresholds on shared runners.
- Update tool/perf/README.md with exact commands and scope of measurements.

## 6. Integrate and review
- Independent spec review, then quality review; fix important issues with regression tests.
- Format touched Dart code, run full Flutter tests/analyzer, browser checks and release web build.
- Run controlled benchmarks sequentially and report measured changes separately from unmeasured expectations.
- Do not commit or push without user request.
