# Automation spec: clinic appointment reminders

Slug: automation-clinic-reminders
Date: 2026-08-20
Mode: **BUILD MINIMAL** -- one n8n workflow, schedule-poll design, shippable today.
Status: spec only; NOT deployed, NOT merged (human-checkpoint rule).

Source intent (contract-verified): automated appointment reminder that reaches patients
before the appointment; channel = text or email, reliability is the deciding factor.
No-show rate is the stated pain.

## Chosen mode

**BUILD MINIMAL.** One workflow: Schedule trigger -> poll booking feed -> filter due
reminders -> dedupe -> send -> observe. No multi-service orchestration. The clinic's
booking system is a single read endpoint (a poll) or a single push webhook (optional);
there is nothing in the requirement that needs a second orchestrator or an always-on
sidecar. BUILD BIG is not justified until the booking-system integration is confirmed
and volume is known.

## Channel alternatives (equal weight)

Both channels share the same workflow skeleton; only the send node and the per-run cost
differ. Numbers marked PENDING are estimates awaiting a live run; integration points
marked UNKNOWN are assumptions the human must confirm against the real booking system.

| column | A. Email (e.g., SendGrid/Postmark) | B. SMS (e.g., Twilio) |
|---|---|---|
| build-cost estimate | ~12 hrs AI-assisted, ~3 days human; free tier covers volume | ~20 hrs AI-assisted, ~4 days human; Twilio account + carrier fees apply |
| maintenance burden / vendor lock-in | Low; email provider swappable, domain-portable, no carrier regulations | Higher; carrier + compliance (consent, A2P 10DLC registration in US), harder to switch |
| reuses | n8n Schedule/HTTP/IF/Set nodes, one observability node, same dedupe pattern reused for any future client reminder loop | Same workflow skeleton as A; reuses the dedupe + observability pattern |
| pros / cons | + cheapest per run, free tier likely covers clinic volume, plain-text send is trivial, no per-message fee | + highest open/read rates, gets in front of patients fastest, works without smartphone email apps |
|  | - lower open rates than SMS, spam-folder risk if domain reputation is cold | - ~$0.0079/msg (Twilio list price, PENDING quote), consent + regulation burden, message length limits |

ROI read: A clears the bar at ~$3.50/yr compute (below); B also clears it (~$45/yr at
100 reminders/wk) but only if the clinic already has patient phone numbers with consent
on file. If neither phone-number consent nor an email field is collected at booking, the
feed has nothing to send to -- that is the real go/no-go gate, not the channel.

## Effort (dual scale)

- Human team: ~3-4 days of design+integration per channel above (booking-feed contract
  negotiation with the clinic's booking vendor dominates).
- AI-assisted: ~12-20 hrs (spec + n8n build), then **$0 ongoing for compute** if the
  clinic runs its own n8n instance; message cost is the only recurring line (email ~$0
  on free tier; SMS ~$41/yr at 100 msgs/wk, PENDING quote).
- Manual equivalent today: front-desk reminder calls, ~2 hrs/day human -> ~10 hrs/wk.
  The automation replaces that recurring cost entirely; ROI is positive from week one.

## Assumptions the human must confirm (UNKNOWN -- never invented)

1. Booking-system integration points: UNKNOWN. The poll endpoint (list bookings in a
   window) and the patient-contact fields (phone, email) must be confirmed with the
   clinic's booking vendor. The design below assumes a read-only poll endpoint exists
   and returns `booking_id`, `appointment_time`, `patient_phone`/`patient_email`.
2. Patient consent: UNKNOWN. Sending requires an opt-in contact channel on file; the
   clinic must confirm how consent is captured and stored.
3. Reminder lead time: assumed 24-48h before appointment, matching "before the
   appointment". Confirm the clinic's preferred window.
4. n8n instance: assumed self-hosted or existing instance; instance cost excluded.
5. No run has been executed: all costs above are estimates = PENDING until a live run.

## Rule-block checklist (n8n-workflow-design)

1. **Trigger inventory**
   - Primary: Schedule trigger, hourly (cron `0 * * * *`). Polls booking feed, sends to
     appointments in the reminder window, stops before the appointment time.
   - Optional (only if the vendor pushes): Webhook trigger (POST) for booking
     create/cancel events. UNKNOWN whether the vendor supports it; schedule-poll is the
     shipped path and needs no webhook.
   - No manual trigger; no other entry points.

2. **Idempotency**
   - Dedupe key = `booking_id` (normalized). Before sending, IF node checks the in-run
     sent-set (static data, rolling 7-day window) AND the feed's booking status; already
     reminded or cancelled bookings are skipped. A re-fired run or a duplicate webhook
     delivery cannot double-send. No send happens without the dedupe gate passing.
   - No double-reminder for reschedules: the key includes the appointment time, so a
     rescheduled slot gets one reminder for the new time.

3. **Retry and error branches**
   - Booking-feed poll (HTTP GET): retry 3x, exponential backoff, timeout set; on final
     failure route to the observability node with `status=feed_error`, no sends.
   - Send node (email or SMS): retry 2x with interval; error output wired to the error
     branch (log + notify the clinic inbox) -- never a silent swallow.
   - Every external call has a retry policy and an error path (self-test pass).

4. **Secrets handling**
   - Provider API key and webhook shared secret live in n8n credentials / instance
     secret store, referenced by credential name. Never inline in node JSON. No secrets
     in workflow JSON exports (strip before committing).

5. **Webhook security**
   - Optional webhook path only: verify `X-Webhook-Signature` (HMAC-SHA256 over the raw
     body with the stored shared secret) in an IF node before processing; 401 on
     mismatch, process branch on match. The shipped schedule-poll path has no inbound
     webhook, so this rule is "not applicable to the shipped path; mandatory if the
     push integration is added".

6. **Observability node**
   - Final Set/HTTP node writes `{run_id, status, duration, sent_count, skipped_count,
     error_count}` to a log sink (file or sheet the clinic can read) on every run --
     success and failure alike. This is the one node that makes a failed run
     diagnosable after the fact.

7. **Cost-per-run estimate**
   - n8n compute: ~8760 runs/yr hourly; per-run cost ~$0.0004 on a typical small
     instance -> **~$3.50/yr** (PENDING until live).
   - Email (SendGrid free tier): $0 for <=100 msgs/day -> $0/yr at clinic volume.
   - SMS (Twilio list price): ~$0.0079/msg -> ~$41/yr at 100 reminders/wk (PENDING
     quote). Total worst case (SMS): ~$45/yr; total email path: ~$3.50/yr.

8. **Notification text (predecessor rule)**
   - Model/patient-facing text is sent with parse mode OFF -- plain text only, never
     through a Markdown or HTML parse mode. A reminder body containing `_` or `*` must
     not be able to kill the send.

## Scope note

This is a client (clinic) deliverable workflow. It is not a hop inside sefi-agents' own
control loop.

## Next gate

Human confirms the three UNKNOWNs (booking-feed endpoint + contact fields, consent
capture, lead-time window) against the real booking system. Until then this spec stays
unbuilt; no deployment, no merge (human-checkpoint rule).