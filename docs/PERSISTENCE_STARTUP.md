# First-launch persistence initialization

Issue #35 investigated recovered CoreData errors in successful CI run
[40245859384](https://github.com/atomantic/PortDeck/actions/runs/40245859384),
at `f439b7e880dcc4e3bc7266ecf542253d679a6d05`.

## Cause and disposition

The app passed SwiftData's default disk configuration directly to
`ModelContainer`. On a fresh simulator installation, its resolved
`Library/Application Support` directory did not exist. CoreData first reported
Cocoa error 512 (`Failed to create file; code = 2`), then explicitly reported
the missing parent directory and successful recovery. The original CI tests
passed; these diagnostics did not establish data loss or an application failure.

On October 26, 2026, the same sequence reproduced with the unchanged startup
path on a newly created iPhone 17 simulator, Xcode 26.3 (17C529), iOS 26.3 runtime.
Before the first unsigned launch, neither Application Support nor `default.store`
existed. The framework recovered and created the store. This pins the immediate
cause to directory initialization, rather than an entitlement failure: creating
the directory before opening the same store removed the diagnostics without
changing signing or sandbox permissions.

`FleetModelStore` now creates the parent of the supplied configuration's resolved
URL before opening disk-backed stores. It preserves SwiftData's default store
location and schema, including previously saved fleets. It does not create a
SQLite file itself, delete or repair an existing store, suppress framework logs,
or fall back to memory on failure. Directory and container errors still reach
the app's existing fatal startup error. Demo and explicitly in-memory launches
skip directory preparation.

## Reproduction and regression checks

Build the pinned native bridge, generate the project with XcodeGen, and build
an unsigned Debug simulator app. Create and boot a dedicated simulator, then
install the app with `xcrun simctl install`. Before launching, use
`xcrun simctl get_app_container <simulator> net.shadowpuppet.PortDeck data`
to confirm that `Library/Application Support` is absent. Launch using
`xcrun simctl launch --console <simulator> net.shadowpuppet.PortDeck`, without
`-demo-data` or `-UseInMemoryStore`, and capture the console output.

Repeat with the fix after uninstalling the app from that dedicated simulator
and reinstalling, confirming the directory is absent again before launch.
The fixed fresh launch created `default.store` with zero `CoreData: error:`
messages. Simply launching a second time against the recovered store is not a
fresh-container comparison.

`FleetModelStoreTests` covers a missing nested directory, disk save and reopen,
preservation and propagation of a conflicting parent-file error, and in-memory
isolation. Hosted CI retains the disk-backed unit-test host and captures its raw
output, failing if the specific missing-parent recovery diagnostic recurs. It
also retains the separately signed native keychain run and its assertions of
exactly two passes, zero skips and zero failures, followed by the existing UI
smoke tests.
