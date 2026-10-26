# Simulator test preparation and timing

CI builds all scheme test products once with `build-for-testing`, ad hoc signing
(`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO`) and the
existing app entitlements. `test-without-building` reuses those products for the
entire unit target and the same four UI smoke tests. No test assertion,
entitlement, skip behavior or app security policy changes. Serial test execution
avoids extra simulator clones for these short suites.

The result gate checks every test result against the summary, rejects skips and
failures, and requires explicit `Passed` results for both native keychain tests
and all four UI contracts. Running unsigned locally remains possible, but does
not satisfy CI's native-keychain evidence requirement.

## Baseline

[Main run 40232887874](https://github.com/atomantic/PortDeck/actions/runs/40232887874),
2026-10-25, macos-26-arm64 image 20261013.0424.1, Xcode 26.6, iOS 26.5:

| Measurement | Before |
| --- | ---: |
| Build & Test job | 1,535 s (25m35s) |
| Combined Run unit tests step | 1,391 s (23m11s) |
| Unsigned unit test bodies | 6.886 s, 135 tests, 2 skipped |
| Signed native test operation (Xcode observer elapsed) | 443.151 s |
| Signed native test bodies | 0.679 s, 2 passed, 0 skipped |
| UI test operation (Xcode observer elapsed) | 200.929 s |

The old step includes build, relink/sign, host installation/launch and testing.
Its Xcode observer elapsed values are not complete command wall times. The old
logs do not isolate signing or boot time, so these cannot be reconstructed as
separate measured baseline phases. Most elapsed time was outside XCTest bodies;
this does not identify compilation as its cause.

## Measurements and failure evidence

`python3 scripts/run_ci_tests.py` records:

- Simulator boot request and readiness wait independently of building. Boot
  starts before the build so cold-runtime migration can overlap compilation;
  readiness wait is the remaining wait after building, not total boot latency.
- Signed build-for-testing wall time, with `-showBuildTimingSummary` in the raw
  log. CodeSign cumulative task time is reported separately; it is included in
  build wall time, not an additional serial phase.
- Test-without-building wall time, including install/host launch overhead, and
  individual XCTest body durations from xcresult. Their difference includes
  other Xcode orchestration and must not be described as pure launch time.
- Runner image, architecture, Xcode version, simulator runtime, counts and
  explicit results for every test.

The job summary reports phase durations, and the `ci-test-evidence` artifact
retains raw logs, JSON metrics, test summary/tree and the xcresult bundle for
seven days, including on failure. Each phase has a deadline (boot readiness
900 s, build 1,200 s, tests 900 s, result queries 60 s). A timeout kills the
command group, records the failed phase and prints at most the last 80 log lines.
The job has a 60-minute outer limit. Failures remain failures.

Compare the PR run's `timings.json` with the hosted baseline above, checking the
runner image/Xcode/runtime before interpreting differences. Local hardware
measurements are validation only and cannot establish hosted speedup. The
hosted after measurements are recorded once CI completes.

The [first instrumented hosted run](https://github.com/atomantic/PortDeck/actions/runs/40270181124)
failed before building or testing: the initial 180-second readiness limit expired
while `com.apple.locationd.migrator` was still migrating the cold simulator. This
is direct startup evidence, not a test flake. The readiness bound is now 900 s,
allowing for the baseline's 611.959-second first test operation; build and test
deadlines and test assertions are unchanged. Failed runs are excluded from the
speed comparison.
