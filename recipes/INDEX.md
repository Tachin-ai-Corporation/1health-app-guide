# Recipe index

Find the pattern you need, open that recipe. Every recipe has the same shape: *Use when · Routes ·
Reference code · Seen in · Pattern · (Primary vs fallback) · Minimal example · Gotchas · Related.*
- **adv** = an advanced, guardrailed pattern (read [setup/conventions.md](../setup/conventions.md) first).
- **Primary vs fallback** appears wherever 1health offers two ways to do the same job: start with the
  primary; the section says exactly when to switch.
- A **⚠ Not yet in 1health's published API docs** banner marks a route 1health supports for
  third-party apps but hasn't documented at agents.1health.io yet — test it against demo first.

**New here?** Read [setup/rules-of-the-road.md](../setup/rules-of-the-road.md) →
[setup/prototype-to-app.md](../setup/prototype-to-app.md), then start with the Foundations below.

## Foundations — start here
| Recipe | For |
|---|---|
| [query-the-data-graph](query-the-data-graph.md) | Read entities + relationships with a projection/filter (`/api/v2/query`) |
| [read-write-custom-data](read-write-custom-data.md) | Store app-specific fields on any instance (`customData`) |
| [schema-discovery](schema-discovery.md) | Discover types, attributes & relationships at runtime |
| [grid-list-views](grid-list-views.md) | Server-defined table/list views with paging (`/v3/health/grid/*`) |
| [api-versions-and-layers](api-versions-and-layers.md) | Pick the right API layer: v1 basement, v2 wrappers, v3 wrappers/fresh |
| [choose-a-read-path](choose-a-read-path.md) | Decide between `/query`, list-by-type, relationship reads, grids, GraphQL |
| [sentinel-values-not-null](sentinel-values-not-null.md) | Decode values once: `"n/a"` / `-1` for unset, `"true_"`/`"false_"` booleans |

## Reading data
| Recipe | For |
|---|---|
| [relationship-path-building](relationship-path-building.md) | Build a `Source.Edge.Target` query path (direction-aware) |
| [graphql-read-path](graphql-read-path.md) | GraphQL as a third read path (relationship-record attrs, tag lists) |
| [query-pagination-and-sorting](query-pagination-and-sorting.md) | Page `/query` with `limit`+`offset`; server `sort` by id, client sort otherwise |
| [bulk-read-and-export](bulk-read-and-export.md) | Export / bulk-read: a `/query` offset loop + client-side filtering |
| [batched-enrichment](batched-enrichment.md) | Batch-enrich rows by id (`id==a,id==b,…`) for a field a list omits |
| [enrich-grid-with-custom-data](enrich-grid-with-custom-data.md) | Join a grid page with bulk customData by id |
| [cohort-definitions](cohort-definitions.md) · **adv** | Define, evaluate, and snapshot a cohort (reusable filter trees) |

## Writing & extending data
| Recipe | For |
|---|---|
| [write-safety-and-fail-closed](write-safety-and-fail-closed.md) | Read-modify-write safely; never treat unreadable as empty |
| [closed-vocabulary-writes](closed-vocabulary-writes.md) | Write into a closed vocabulary: attach → parse the 400 → strip → retry |
| [read-after-write-consistency](read-after-write-consistency.md) | Poll-with-backoff for read-after-write consistency |
| [environment-capability-detection](environment-capability-detection.md) | Detect a feature not deployed in this environment (404) |
| [typed-custom-field-definitions](typed-custom-field-definitions.md) | Admin-defined typed custom fields (`/v3/custom-data`) |
| [boi-instance-attribute-write](boi-instance-attribute-write.md) | Write a raw BOI instance attribute (the v1 basement) |
| [link-and-unlink-instances](link-and-unlink-instances.md) | Create/delete a relationship between two existing instances |
| [bulk-import](bulk-import.md) | Bulk-import records from a file; track the job in the import log |
| [audit-trail-in-custom-data](audit-trail-in-custom-data.md) | Append-only audit log in customData (⏳ journey-log APIs coming) |
| [per-user-preferences](per-user-preferences.md) | Per-user state: Person customData vs localStorage |
| [custom-data-as-state-machine](custom-data-as-state-machine.md) · **adv** | customData as process state — only when the workflow can't model it |

## Workflows (journeys, steps, campaigns)
| Recipe | For |
|---|---|
| [workflows-journeys-steps](workflows-journeys-steps.md) | Campaign→Template→Journey→Steps; the 3 step-submit recipes |
| [workflows-without-a-patient](workflows-without-a-patient.md) | Run any process as a workflow — no patient step, no audience, no subject |
| [dynamic-step-fields](dynamic-step-fields.md) | Resolve step form fields by `label` (per-env GUIDs) |
| [resolve-actionable-step](resolve-actionable-step.md) | Find the actionable step via the canonical relationship |
| [provision-templates-and-campaigns](provision-templates-and-campaigns.md) | Find/clone/publish a template + create/activate a campaign |
| [campaign-lifecycle-and-audience](campaign-lifecycle-and-audience.md) | Run / cancel / finish / restart a campaign; target it by tags |
| [template-versions-draft-publish](template-versions-draft-publish.md) | Template drafts vs published vs history; clone-to-draft; publish |
| [batch-step-submit-from-spreadsheet](batch-step-submit-from-spreadsheet.md) | Submit one step across a whole campaign from a spreadsheet |
| [step-preview-mode](step-preview-mode.md) | Preview how a step renders, with no journey or order |
| [step-config-notifications-webhooks](step-config-notifications-webhooks.md) | Read-modify-write step notifications & webhooks |
| [stamp-config-onto-journey](stamp-config-onto-journey.md) | Copy step config onto a new journey (clone doesn't carry it) |
| [async-trigger-and-poll](async-trigger-and-poll.md) | Trigger an async backend action; poll a customData sentinel |
| [journey-orchestration](journey-orchestration.md) | End-to-end journey run; retire via UAT, not delete |
| [campaign-dashboard-aggregation](campaign-dashboard-aggregation.md) | Campaign KPI counts (`/workflow-campaign/{id}/dashboard`) |
| [job-worklist-fanout](job-worklist-fanout.md) · **adv** | Denormalized in-flight job worklist + bounded fan-out |
| [workflow-config-diagnostics](workflow-config-diagnostics.md) · **adv** | Dump every step's config to debug webhooks/notifications |
| [env-pinned-campaign](env-pinned-campaign.md) · **adv** | Pin one campaign per env by env var (no discovery — tradeoff) |
| [decision-steps](decision-steps.md) · **adv** | Author conditional branch points in a workflow template |

## Files, comments & collaboration
| Recipe | For |
|---|---|
| [attachments](attachments.md) | Upload/download/delete files (step field vs free-standing) |
| [comments](comments.md) | List (via grid) and post journey comments |
| [bulk-tagging](bulk-tagging.md) | Tag instances in bulk (GraphQL list + REST apply/remove) |
| [bulk-assignment](bulk-assignment.md) | Assign/unassign users to journeys in bulk |
| [saved-grid-views](saved-grid-views.md) | Personal and shared saved grid views (`/v2/grid-config`) |

## Sharing & partner orgs
| Recipe | For |
|---|---|
| [share-with-partner-org](share-with-partner-org.md) | Share an instance/campaign with a partner org |
| [partner-org-typeahead](partner-org-typeahead.md) | Search approved partner orgs (debounced typeahead) |
| [partnership-relationship-types](partnership-relationship-types.md) | Toggle partnership status and each relationship type independently |
| [message-a-partner-contact-point](message-a-partner-contact-point.md) | Message a partner's email/fax/mobile contact point (fax preview) |
| [mirror-pair-bidirectional-share](mirror-pair-bidirectional-share.md) · **adv** | Present a one-way share primitive as bidirectional |
| [auto-mirror-on-first-write](auto-mirror-on-first-write.md) · **adv** | Lazily create the reciprocal share on first write |
| [shareable-containers](shareable-containers.md) · **adv** | Assemble a files+journeys "container" to share |

## Org & tenant onboarding
| Recipe | For |
|---|---|
| [self-service-org-onboarding-by-npi](self-service-org-onboarding-by-npi.md) | Onboard an org by NPI (verify → find/create → invite) |
| [partner-invitation-and-pin](partner-invitation-and-pin.md) | Invite a partner org + extract its PIN; recover rejects |
| [grant-app-access](grant-app-access.md) | Allow an org to use your external application |
| [deep-link-invite-url](deep-link-invite-url.md) | Generate a deep-link invite URL with an embedded PIN |
| [org-claim-status-lookup](org-claim-status-lookup.md) | Look up an org's claim/partnership status, PII-safe |
| [look-then-create](look-then-create.md) | Avoid duplicate-conflict 400s (look, then create) |
| [scoped-api-key-with-role](scoped-api-key-with-role.md) | Mint a scoped API key (resolve the role id first) |
| [org-and-tenant-profile-reads](org-and-tenant-profile-reads.md) | Read the right org/tenant profile for the id you actually hold |
| [org-identity-and-branding-assets](org-identity-and-branding-assets.md) | Update an org's identity fields and logo/icon assets |
| [add-users-to-a-tenant](add-users-to-a-tenant.md) | Pre-approve (incl. CSV) or invite users; approve/deny/deactivate |
| [email-domain-allowlist](email-domain-allowlist.md) · **adv** | Restrict self-registration to approved email domains |
| [tenant-security-policy](tenant-security-policy.md) · **adv** | Set a tenant's lockout & session policy |
| [ndjson-progress-streaming](ndjson-progress-streaming.md) | Stream multi-call server progress as NDJSON |
| [tenant-provisioning](tenant-provisioning.md) · **adv** | Provision a tenant + reuse-by-name |
| [cross-origin-tenant-switch](cross-origin-tenant-switch.md) · **adv** | Switch tenant + verify token propagation |
| [register-console-application](register-console-application.md) · **adv** | Register your app as a console/external application |

## Patients, orders & clinical records
| Recipe | For |
|---|---|
| [patient-crud](patient-crud.md) | Patient + sub-resource CRUD (`/v3/patient/*`) |
| [patient-find](patient-find.md) | Scored find (primary) + grid / full-text search (`/v3/patient/find`) |
| [patient-documents](patient-documents.md) | Patient documents (base64 JSON; expiring URLs) |
| [deferred-record-creation](deferred-record-creation.md) | Create the patient at commit (v3 first; upsert-with-org-attach fallback) |
| [external-record-to-medical-record](external-record-to-medical-record.md) | External extract → normalize → attach → read back |
| [patient-insurance](patient-insurance.md) | Insurance from the right scope: self, org, or order |
| [orders-and-master-orders](orders-and-master-orders.md) | Create, advance, and read orders; an order is a journey (different id) |
| [catalog-vs-instance-modeling](catalog-vs-instance-modeling.md) | Separate a catalog definition from the instances made from it |
| [test-catalog-modeling](test-catalog-modeling.md) | A test's clinical definition vs its orderable product listing |
| [results-ingestion](results-ingestion.md) | Submit a test result, structured or as a file |
| [platform-generated-documents](platform-generated-documents.md) | Let 1health generate requisitions/result PDFs instead of compositing |

## External integrations (done right)
| Recipe | For |
|---|---|
| [public-reference-api-proxy](public-reference-api-proxy.md) | Server CORS proxy for a public reference API (NPI/ICD-10/…) |
| [cache-reference-data-in-custom-data](cache-reference-data-in-custom-data.md) | Cache external reference data into customData |
| [external-systems-and-id-mapping](external-systems-and-id-mapping.md) | Map a record to its id in an outside system (EHR MRN, member id, …) |
| [deidentify-before-external-ai](deidentify-before-external-ai.md) | De-identification gate before any external AI call |
| [external-job-pipeline](external-job-pipeline.md) | External job: idempotent submit + poll + persist-before-expiry |
| [client-side-pdf-authoring](client-side-pdf-authoring.md) | Normalize intake into one PDF in the browser |
| [server-side-pdf-rendering](server-side-pdf-rendering.md) | Stamp/render a PDF server-side |
| [fixed-ip-partner-relay](fixed-ip-partner-relay.md) · **adv** | Fixed-IP relay for an IP-allowlisting partner |
| [knowledge-base-proxy](knowledge-base-proxy.md) · **adv** | Curated KB/RAG proxy (open read, gated write) |
| [external-approval-state-machine](external-approval-state-machine.md) · **adv** | Long external-approval workflow, state in customData |

## Communications
| Recipe | For |
|---|---|
| [native-email-and-sms](native-email-and-sms.md) | Send email/SMS via 1health (`/v2/email/send`, `/v2/twilio/send`) |
| [verify-a-contact-channel](verify-a-contact-channel.md) | Prove someone controls an email/phone: public OTP, link, or PIN check |
| [custom-otp](custom-otp.md) · **adv** | Self-rolled OTP — the fallback when the platform OTP refuses your session |

## Agreements & compliance
| Recipe | For |
|---|---|
| [baa-gating](baa-gating.md) | Gate app access on BAA acceptance (`/v2/agreement/{type}`) |
| [sanitizing-bff-proxy](sanitizing-bff-proxy.md) | Normalize/sanitize an upstream response or error |
| [baa-status-split-identity](baa-status-split-identity.md) · **adv** | Read BAA status with a service key; accept as the user |

## App architecture & security
| Recipe | For |
|---|---|
| [server-side-authorization](server-side-authorization.md) | Server-side caller resolution + resource-ownership authz |
| [request-funnel-and-error-tiers](request-funnel-and-error-tiers.md) | One request wrapper: error tiers, a global spinner, blob errors |
| [auth-forcing-route-wrapper](auth-forcing-route-wrapper.md) | A wrapper that authorizes before the route body runs |
| [fail-closed-dedup-ledger](fail-closed-dedup-ledger.md) | A dedup ledger in customData for non-idempotent writes |
| [multi-alias-payload-parsing](multi-alias-payload-parsing.md) | Parse heterogeneous partner payloads defensively |
| [data-seam-module](data-seam-module.md) | One module the UI reads data through (current + future source) |
| [url-driven-state](url-driven-state.md) | Put identifiers in the URL; rebuild state from 1health on load |
| [poll-and-diff-live-sync](poll-and-diff-live-sync.md) | Poll a record and diff for near-real-time UI |
| [split-identity-service-key](split-identity-service-key.md) · **adv** | User token vs privileged service key, per-op, enforced |
| [cross-tenant-read-proxy](cross-tenant-read-proxy.md) · **adv** | Read-only cross-tenant proxy (flag + fallback) |
| [isomorphic-trust-boundary-core](isomorphic-trust-boundary-core.md) · **adv** | Share one query/parse core across trust boundaries |
| [qr-device-session-handoff](qr-device-session-handoff.md) · **adv** | Sealed single-use QR device-session hand-off |
| [provider-minted-magic-link](provider-minted-magic-link.md) · **adv** | Provider-minted magic link, verified downstream |
| [in-app-agent-docs-mirror](in-app-agent-docs-mirror.md) · **adv** | Mirror agents.1health.io docs in-app (SSRF allowlist) |
| [in-app-api-inspector](in-app-api-inspector.md) · **adv** | Live in-app API call inspector (devtool) |
| [demo-mode-seam](demo-mode-seam.md) · **adv** | Isolate a demo session from a real one |
| [capability-probe](capability-probe.md) · **adv** | Re-runnable probe of what your token may do |

## Auth & session
(Core auth flow is in [setup/auth-and-launch.md](../setup/auth-and-launch.md); testing as each role is in [setup/qa-and-local-testing.md](../setup/qa-and-local-testing.md).)
| Recipe | For |
|---|---|
| [resilient-api-client](resilient-api-client.md) | Harden the client: single-flight refresh, a bare client for public calls |
| [enrich-session-in-token-route](enrich-session-in-token-route.md) | Seed session ids inside the token route (avoid a 2nd route) |
| [qa-launch-with-api-key](qa-launch-with-api-key.md) | Sign a local or dev/stage build in as each QA role (never production) |
| [survive-an-auth-redirect](survive-an-auth-redirect.md) | Keep your params intact across a hosted-login redirect |
| [iframe-embedding-cookies](iframe-embedding-cookies.md) | Cookies that survive a cross-site iframe (CHIPS) |
| [server-side-signout](server-side-signout.md) · **adv** | Complete server-side sign-out |
| [return-to-path](return-to-path.md) · **adv** | Return-to path across a hosted-login bounce |
| [auth-url-branding](auth-url-branding.md) · **adv** | Brand the hosted login/registration pages |

---
**Don't do these:** see [setup/anti-patterns.md](../setup/anti-patterns.md) (non-1health datastores,
localStorage-as-datastore, third-party mailers by default, hardcoded env ids, skipping `authFetch`,
async bulk-export jobs, PHI in URLs or logs, inventing a patient to fit a workflow, sign-in shortcuts,
admin-only QA, QA keys in production).
