# Manual conversion pause (build 47)

A manual pause used to cancel the iPhone's conversion task and polling only. The Cloud Run worker was not informed and could complete all remaining pages.

Manual pause now persists a pending server stop and sends the existing authenticated cancellation request with the original idempotency key. The server's cancellation barrier stops new work cooperatively and rejects later result publication. Source files, completed page checkpoints, and exact request cache entries remain attached to the same job. Explicit Resume retains that request ID; the existing server restart path reuses compatible saved work.

The app disables Resume until the server accepts the stop request, retries connection failures across reconnection/relaunch, and distinguishes pending, acknowledged, and already-finished outcomes. Old manually paused records without an acknowledgement are reconciled when loaded. Automatic background continuation is unchanged; a manual pause clears that flag.

Creation/upload cancellation checkpoints and the late-created-job callback prevent the local producer from continuing an upload/commit or rearming the background watcher after a pause. An HTTP error from that unwinding producer cannot replace the paused/cancelled state.

This is a cooperative stop, not a retroactive billing adjustment. Calls already accepted by the model may finish and incur charges during the stop interval. Unacknowledged network failures may allow server work to continue; the app says so. A result completed before the request arrived is downloaded on Resume without repeating conversion. The backend ledger records this stop as cancellation, because the established cancellation API is the compatibility barrier used by this client.

Validation: three new XCTest cases cover manual pause at page 85/219, durable pending state, resume blocking, confirmed outcomes with the same request ID, and connection-failure behavior. The backend's existing 15 cancellation and 24 cost-control tests passed locally. Full Xcode tests and device IPA are built by Codemagic.
