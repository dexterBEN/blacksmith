# Resource configuration API — Save-only v1

These endpoints read/replace configuration for an **existing** Resource. They save design intent in PostgreSQL; they never create a bucket, contact GCP, validate IAM or change credentials. No frontend integration or deployment status is implied.

For atomic Resource+configuration creation, stable client UUIDs, revisions and tile
uniqueness, see [the configured persistence contract](resource-persistence-api.md).
The dedicated configuration PUT remains unconditional and now advances the owning
Resource's change revision; its document schemaVersion and response shape are unchanged.

Prerequisite: the Issue #46 / PR #47 migration `20261025205111_AddResourceConfigurations` must be applied in the target environment. This increment adds no migration. Tests apply it only to their disposable databases.

## Routes and JSON contract

```http
GET /resources/{resourceId}/configuration
PUT /resources/{resourceId}/configuration
Content-Type: application/json
```

The path must identify an existing Resource. The server reads its provider type and Design relationship from the database. It accepts configuration v1 only for exact type `gcp.storage.bucket`. A nullable catalog reference is supported for legacy rows; if a classification is present its code must be `storage`. The generic catalog alone never establishes the provider type.

Minimal PUT body:

```json
{
  "schemaVersion": 1,
  "configuration": {
    "projectId": "example-project-123",
    "bucketName": "blacksmith-example-assets",
    "location": "europe-west9"
  }
}
```

PUT returns **200 OK** for both first configuration creation and replacement. GET returns the same canonical value shape:

```json
{
  "resourceId": "11111111-1111-1111-1111-111111111111",
  "schemaVersion": 1,
  "configuration": {
    "projectId": "example-project-123",
    "bucketName": "blacksmith-example-assets",
    "location": "europe-west9",
    "storageClass": "STANDARD",
    "uniformBucketLevelAccess": true,
    "publicAccessPrevention": "enforced"
  }
}
```

Identifiers are illustrative, not a deployment request or a checked available bucket name. `configuration` is a JSON object on the wire and native `jsonb` in PostgreSQL. SchemaVersion is a separate field/column, not duplicated inside the document. Do not send `resourceId`, `type` or `designId` in the PUT envelope; it accepts only `schemaVersion` and `configuration`.

## v1 rules

All keys and values are case sensitive. Input is rejected rather than silently trimmed or lowercased.

| Field | Rule |
|---|---|
| `schemaVersion` | Required JSON integer `1`; strings, decimals and other versions are rejected. |
| `configuration` | Required JSON object; arrays, primitives, JSON strings and null are rejected. |
| `projectId` | Required, 6–30 lowercase ASCII letters/digits/hyphens; starts with a letter, ends with a letter/digit; `google` and `ssl` substrings are unsupported. Project display names, numbers and historical domain-scoped formats are outside v1. |
| `bucketName` | Required, conservative 3–63-character lowercase ASCII letter/digit/hyphen subset; starts/ends with a letter/digit. `goog` prefix and `g[o0]{2}gle` fragments are rejected. Dots/underscores are intentionally outside this API's subset. |
| `location` | Required, exactly `europe-west9`, `us-central1` or `northamerica-northeast1`. No default region, multi-region or dual-region in v1. |
| `storageClass` | Optional input, but if present must be string `STANDARD`. Always materialized in the saved/returned canonical document. |
| `uniformBucketLevelAccess` | Optional input, but if present must be boolean `true`. Always materialized. |
| `publicAccessPrevention` | Optional input, but if present must be string `enforced`. Always materialized. |
| `softDeleteRetentionDays` | **Not supported**; rejected as an unknown field. No seven-day policy or other soft-delete default is imposed by this API. |

Regional choices were checked against [Google's location list](https://docs.cloud.google.com/storage/docs/locations). This is an explicit product subset. Format checks follow conservative subsets of the documented [project ID](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects) and [bucket naming](https://docs.cloud.google.com/storage/docs/buckets#naming) rules. They do not reserve a name, prove project existence, guarantee provider acceptance, or authorize provisioning.

Unknown keys are rejected in both envelope and document. Duplicate logical keys, including case variants and JSON-escaped equivalents, are rejected. The flat allowlist rejects obvious credential fields such as `private_key`, tokens, credential objects and arbitrary nested provider requests. It is not a generic secret detector: never put secrets into otherwise permitted resource names.

The request body limit is **16,384 UTF-8 bytes**; validation also caps traversal depth at **8**, including the envelope. Kestrel's endpoint limit applies before parsing; Content-Length and parsed-document checks also cover in-process HTTP tests. Existing endpoints' global JSON options are unchanged. No request JSON logging is introduced and application errors contain fixed messages/known field names, not user values.

## Status and overwrite semantics

| Situation | Result |
|---|---|
| GET supported configuration | 200, canonical representation |
| GET unknown Resource or absent configuration | 404, `{"error":"Resource configuration not found."}`; no synthetic document |
| PUT valid document to an existing eligible Resource | 200 for create/replace |
| PUT valid document to an unknown Resource | 404, `{"error":"Resource not found."}`; no implicit Resource creation |
| Unsupported type/catalog, version, fields, format or depth | 400 with an `error` message |
| Malformed JSON / unreadable request body | 400 using ASP.NET's normal validation response |
| Request exceeds the body limit | 413 |
| GET historical document with unsupported version/structure/size | 409 with a generic error, never the raw document |
| Legacy metadata PUT changes a configured Resource's type or gives a bucket configuration an incompatible catalog classification | 400; previous state retained |

JSON parsing/validation precedes Resource lookup for PUT, so an invalid request may return 400/413 even for an unknown ID. Non-GUID route IDs and unsupported content types use the framework's normal 404/415 behavior.

PUT replaces the **complete** configuration, not a patch: all three mandatory fields are required each time. A valid v1 PUT can explicitly replace a historical unsupported document on an eligible Resource. GET can materialize missing fixed values in its canonical response without writing the legacy stored document.

Writes are transactional for one Resource. A short parent-row lock in PostgreSQL serializes configuration insertion/replacement and metadata type updates, preventing duplicate first inserts and incompatible type/configuration races between these API paths. This is **not optimistic concurrency control**: there is no ETag, If-Match, revision or stale-editor detection. Simultaneous valid edits use last successful write wins; clients must not assume their older values were preserved. Cross-request retry/reconciliation UX remains future work.

## Legacy behavior and lifecycle

- Resource ID, Design ID, name, type and coordinates are not changed by configuration PUT.
- Existing metadata DTOs and GET/list/POST/PUT response shapes remain unchanged; a metadata-only PUT does not erase configuration.
- Unconfigured Resources can still change type through the existing metadata path. Configured Resources require an explicit future conversion flow; this increment rejects type changes instead of silently carrying incompatible JSON.
- Multiple Resources in one Design have independent documents; no tile uniqueness rule is added.
- `DELETE /resources/{id}` keeps its existing cascade behavior for the owned configuration. There is no new configuration DELETE endpoint. Design deletion remains restrictive.
- No Google SDK, cloud endpoint, deployment state, UI or credentials are involved in these operations.
