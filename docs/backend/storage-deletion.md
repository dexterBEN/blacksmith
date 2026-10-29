# Explicit deletion of a Resource and its empty Cloud Storage bucket

This backend-only workflow deletes one deployed Cloud Storage resource. It is separate from metadata-only `DELETE /resources/{id}` and `DELETE /designs/{id}`, which never contact Google. No frontend deletion action is added in this slice. No user audit log is introduced.

## Prerequisites

- Apply migration `20261029053949_AddStorageDeletions` deliberately before running the updated backend. Startup does not migrate the database. Do not downgrade while deletions are unresolved: receipts are recovery evidence.
- Existing deployment policy still applies: ASP.NET Core `Development`, `BlacksmithDeployment__Enabled=true` and an explicitly approved project in `BlacksmithDeployment__ApprovedProjects`.
- The backend ADC identity needs Cloud Resource Manager project lookup, bucket metadata read and `storage.buckets.delete` permissions. No object deletion permission or recursive object deletion is used.
- Only resources with a recorded deployment target are supported. Resolve all `pending` or `unknown` deployment operations first. An undeployed Resource uses the existing local DELETE endpoint.
- Use the trusted local connection described in the deployment contract. This is not a multi-user authentication/authorization system.

## API

Base route:

```text
/designs/{designId}/resources/{resourceId}/deletions/{operationId}
```

Clients generate a nonempty UUID `operationId` and retain it to recover a lost response. The first accepted deletion permanently binds the Resource UUID to this operation. Another operation ID for the same Resource returns `404`; use the original receipt.

| Request | Behavior |
| --- | --- |
| `PUT` base route | Explicitly claim and execute empty-bucket deletion |
| `GET` base route | Read database receipt only; available after Resource or Design removal |
| `POST` base route + `/reconcile` | Check bucket presence and ownership, without deleting a bucket; finish local cleanup only when absence is confirmed |
| `POST` base route + `/retry/{requestId}` | Explicit retry after a confirmed failure, with a new client-generated UUID |

PUT and retry require both:

```http
X-Blacksmith-Delete-Consent: true
If-Match: "resource-<resource UUID without hyphens>-r<revision>"
```

Obtain the strong Resource ETag from `GET /resources/{resourceId}?include=configuration`. Retry uses the original frozen revision. Missing consent returns `400`; missing If-Match returns `428`; malformed tags return `400`; a stale first-write/retry revision returns `412`. Scope mismatches and missing resources/receipts return `404`. Disallowed projects or disabled environments return `403`. Unresolved deployment or deletion states and incompatible resource kinds return an explicit conflict/validation response.

Replays of the original PUT return the recorded outcome without another cloud call. Reusing a retry UUID does not repeat the mutation. GET and reconciliation do not require deletion consent; reconciliation still requires the local deployment policy and approved target project.

The response contains operation ID, Resource ID, Design ID, frozen revision, project, bucket, location, status, code and update timestamp. Ownership markers and credentials are never returned. Responses are `202` while an execution lease is active and `200` for recorded outcomes, including `failed` and `unknown`; clients must inspect `status` and `code`. GET always returns `200` when the receipt exists.

## Safety and recovery

1. Lock the Resource using the existing PostgreSQL advisory/row-lock transaction mechanism. Verify ownership by Design, revision and recorded deployment target. The current editable JSON is not used to select a deletion target.
2. Commit a durable deletion receipt and attempt before calling Google. Once accepted, normal Resource metadata/configuration writes, legacy local DELETE, UUID reuse and deployment dispatch/replay are blocked by the deletion lifecycle, including after a failed attempt. There is no cancel/unfreeze endpoint in this slice.
3. Resolve the configured project's numeric identity and fetch the bucket. Verify project, Resource/ownership labels and existing managed-bucket settings. An unrelated bucket is never deleted. An absent bucket is already a completed remote deletion.
4. Call `DeleteBucketAsync` with `DeleteObjects=false`, the observed metageneration precondition and SDK mutation retries disabled. The service never enumerates or deletes objects. A nonempty bucket is rejected by Google and retains local recovery data.
5. On confirmed deletion/absence, remove the Resource, its saved configuration, deployment operations and their attempts, and update the receipt to `succeeded` in one PostgreSQL transaction. Keep the Design, resource catalog and unrelated resources.

Typical failure codes include `bucket_not_empty`, `provider_rejected`, `unrelated_bucket` and `remote_changed`. Fix the external condition and request an explicit retry with fresh consent. Settings/label mismatches require investigation rather than bypassing ownership verification.

A timeout, ambiguous response or provider exception records `unknown` and retains all local information. Do not automatically retry the mutation. Reconcile first. If the owned bucket still exists, reconciliation records `failed/bucket_still_exists`; a deliberate retry may follow. If the bucket is absent, reconciliation completes local cleanup without another delete. An unrelated replacement remains protected.

A committed claim has a 45-second lease and the provider call has a 20-second deadline. A process crash leaves `pending`; once its lease expires, reads expose `unknown/execution_interrupted`. Reconciliation uses a new attempt identifier, and superseded completions cannot overwrite a newer claim. A database cleanup failure similarly leaves a recoverable receipt and rolls back the local aggregate; reconcile after lease expiry.

Deletion receipts and attempt identifiers survive Resource/Design deletion for recovery, idempotency and prevention of accidental UUID resurrection. They are technical lifecycle records, not the future actor/action/date audit system. Receipt purging, cancellation, recursive/nonempty deletion, bulk Design destruction and UI integration are deferred. Google retention/soft-delete policies and billing rules remain provider-controlled; this API does not override them.
