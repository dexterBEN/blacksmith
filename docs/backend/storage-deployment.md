# Cloud Storage Save & Deploy — local development slice

The 3D configuration dialog retains **Save configuration**, which never contacts Google.
**Save & Deploy** explicitly saves one configured Resource and records a durable operation,
then attempts to create/verify its bucket. Header Save, placement, startup and Open do not deploy.
The other GCP resource kinds remain local and cannot be provisioned by this API.

## Authorization and prerequisites

Deployment is **off by default** and permitted only in ASP.NET Core `Development`.
Before enabling it, review the exact project, bucket, supported location, operator identity,
possible Google charges and cleanup plan. A live smoke test is a separate, explicit approval.
There is no provisioner or delete operation in normal tests/CI.

Supply these values externally to the API process, never in a tracked configuration file:

- `BlacksmithDeployment__Enabled=true`
- `BlacksmithDeployment__ApprovedProjects__0=<explicit approved project ID>`
- Existing `ConnectionStrings__BlacksmithDb` and valid Application Default Credentials.

Launch Godot with `BLACKSMITH_BACKEND_URL` pointing to the intended local API if needed.
No deployment token is required by the frontend, launchers or local API. The consent
checkbox requires a valid configuration and an idle, resolved request state; it does
not depend on an environment variable. The API still requires Development mode,
explicit deployment enablement, an approved project and consent for cloud mutations.
After an ambiguous response, **Check Save** reads only database metadata; **Check deployment**
explicitly requests a read-only provider verification.
Keep this single-operator development endpoint on a trusted local connection; it is not a hosted
multi-user security model. Use TLS for transport beyond a trusted local environment.

The provider uses the backend's ADC identity, not the frontend's gcloud account or a project
inferred from ADC. It resolves the **configured** project ID to its canonical project number
with Cloud Resource Manager before touching Storage. Required permissions include
`resourcemanager.projects.get`, `storage.buckets.get` and `storage.buckets.create`; use a
narrowly scoped IAM grant, not Owner/Editor. No credentials belong in ResourceConfiguration.
No IAM or ADC changes are made automatically.

The additive `20261027011918_AddStorageDeployments` migration must be applied through the
normal, separately authorized database procedure before running this version against a database.
It creates two tables and preserves all existing resources/configurations. Running the API does
not apply migrations. This issue's validation migrates only disposable test databases.
Do not downgrade/drop deployment records while a real or unresolved bucket may exist: the
ownership marker and operation are recovery evidence.

The legacy `POST /cloud_services/create-bucket` returns **410 Gone** with
`legacy_provisioning_disabled`. It cannot bypass this policy or resolve ADC. Ping is unchanged.
The old Dart HTTP adapter remains solely for compatibility; grid interactions never invoke it.

## Contract

The initial command uses the existing configured Resource payload:

```http
PUT /designs/{designId}/resources/{resourceId}/deployments/{operationId}
If-None-Match: *
Content-Type: application/json
X-Blacksmith-Deployment-Token: <private runtime token>
X-Blacksmith-Deploy-Consent: true
```

For an existing Resource, replace `If-None-Match` with the strong `If-Match` ETag returned by
`GET /resources/{id}?include=configuration`. Reuse stable UUIDs across an uncertain command.

```json
{
  "name": "Cloud Storage",
  "type": "gcp.storage.bucket",
  "resourceTypeId": "10000000-0000-0000-0000-000000000002",
  "x": 3,
  "y": 2,
  "configuration": {
    "schemaVersion": 1,
    "configuration": {
      "projectId": "example-project-123",
      "bucketName": "replace-with-approved-unique-name",
      "location": "europe-west9",
      "storageClass": "STANDARD",
      "uniformBucketLevelAccess": true,
      "publicAccessPrevention": "enforced"
    }
  }
}
```

The project/bucket above are examples, not approval or application defaults. The existing v1
validator accepts `europe-west9`, `us-central1`, `northamerica-northeast1` and normalizes omitted
security defaults. Unsupported options are rejected. The request limit remains 16 KiB.

Response: **200** for a recorded terminal outcome, **202** while pending:

```text
{ resource: <canonical Resource aggregate including deployment>, deployment: {
    id, resourceId, designId, resourceRevision, projectId, bucketName, location,
    status, code, updatedAtUtc, remoteProjectNumber, remoteBucketId,
    remoteMetageneration, ownershipVerified
} }
```

HTTP 200 means the command has a durable answer; inspect `deployment.status` for cloud success.
A provider rejection returns a saved Resource plus `failed`, not a discarded configuration.
Operation IDs/revisions and saved Resource data survive a full frontend restart.
The aggregate's optional `deployment` property contains its most recent operation; absence
means **not requested**. A later configuration revision does not erase an older deployment.
The UI explicitly labels an outcome belonging to an older revision.

Additional routes under the same `{operationId}`:

| Method / suffix | Effect | Authorization |
| --- | --- | --- |
| `GET` | Database-only status | Metadata access; no ADC or Google calls |
| `POST /reconcile` | Read-only Google verification, persist observed result | Local token and approved project |
| `POST /retry/{requestId}` | Explicitly retry a known failed or never-dispatched command | Local token, consent, current/original `If-Match` |

Unauthorized/disabled/unapproved requests fail before saving or calling Google. Stale revision:
412; missing precondition: 428; changed operation intent or locked target: 409. Error codes and
messages are fixed/sanitized; Google error bodies are not returned. A retry ID is durably consumed
once, even if its response is lost. Repeating a successful/unknown command never creates again.

## Transaction and outcome model

`storage_deployments` stores immutable target/configuration/revision/request hash, a server-owned
random ownership marker, current status/claim lease and verified remote identity. Its unique
Resource/revision constraint and PostgreSQL advisory/row locks serialize concurrent intents.
`storage_deployment_attempts` stores consumed request IDs to deduplicate explicit retries.
These are bounded provisioning records, not a generic scheduler or collaborative action log.

Resource + configuration + initial operation commit in **one PostgreSQL transaction**. The
provider call happens **after** commit, outside any database transaction. A durable claim is
recorded before dispatch. The provider has a 20-second cancellation budget; a 45-second expired
claim is exposed as unknown. There is no automatic background retry.

| Saved DB state | Deployment | Meaning / next action |
| --- | --- | --- |
| Resource/configuration saved, no operation | not_requested | Save-only; Google untouched |
| Intent committed, not dispatched | pending / queued | Same operation may be deliberately resumed |
| Claimed operation | pending | Wait, then read its status |
| Confirmed owner/project/settings | succeeded | Verified at the recorded observation time |
| Known refusal or unrelated bucket | failed | Configuration remains saved; review before retry |
| Lost response, timeout, expired claim, unverifiable read | unknown | Read/reconcile the same operation; never create automatically |

The Google provider first reads the exact bucket name. It requires **all** of: matching project
number, server-generated ownership label and Resource-ID label, location, STANDARD, uniform
access and enforced public-access prevention. A matching global name alone never establishes
ownership. Creation sets these fields, uses `RetryOptions.Never`, and always reads back the
result; a 409 is verified by the same ownership rules. Reconciliation never mutates Google.
Ownership labels are correlation evidence within the trusted project/IAM boundary, not
protection against an adversary who can edit that project's bucket metadata.

Once a Resource has a deployment intent, this slice does not permit deploying it to a different
configuration/target, moving it to another Design or deleting its ownership record through CRUD.
Save-only editing remains available, but an old outcome is never represented as deployment of
the new revision. An unresolved earlier operation must be reconciled before another revision.
A missing bucket after an ambiguous write stays unknown conservatively; it does not authorize
blind recreation. Failed configuration/security verification requires operator investigation.
There is no automatic deletion/compensation and no bucket-delete API.

## Reproducible fake-provider validation

Use an isolated local PostgreSQL server with CREATE DATABASE permission for backend tests.
`BLACKSMITH_TEST_POSTGRES` is a private runtime connection string; do not put it in command
history or reports. The fixtures create/drop only databases named with their random test prefix.

```bash
# Backend SDK 8; run inside the existing backend Dev Container.
dotnet test BlacksmithBackend.sln -c Release

# Frontend, from frontend/src; bindings precede native checks.
dart run build_runner build --delete-conflicting-outputs
dart analyze
dart test

# From repository root; this API fixture injects a fake in test composition only.
python3 frontend/scripts/start-design-test-backend.py CONTAINER --deployment --port 5148
python3 frontend/scripts/test-godot.py --deployment http://CONTAINER_IP:5148 \
  --trace-network --timeout 600 --output /tmp/blacksmith-deployment-check
# Stop the exact RUN_PATH printed by the first command to drop its temporary DB.
python3 frontend/scripts/start-design-test-backend.py CONTAINER --stop RUN_PATH
```

The native harness checks a test-only marker before starting; it refuses an ordinary API.
It drives the real production Godot entrypoint, native controls, Dart repository, ASP.NET API,
EF and PostgreSQL, simulates a lost provider/HTTP response, reconciles without creation, fully
quits Godot, and opens the same Design in a new process. The production API has no switch
that selects a fake provider. The fixture does not access ADC and creates no GCP resources.
