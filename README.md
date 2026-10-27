# SAAMEP

SAAMEP is an offline-first exam-preparation app built with Flutter and SQLite.
It includes role-based student, teacher, parent, and admin experiences; an
interactive quiz engine; offline study topics; local score tracking; cloud
sync; and optional Grok-powered explanations.

## Source layout

* `lib/frontend/` contains role-specific screens, shared widgets, and visual
  constants.
* `lib/backend/` contains authentication, AI, secure-session, and cloud-sync
  services, supporting utilities, API configuration, and data models.
* `lib/database/` contains the SQLite helper and per-platform database factory
  setup.

## Run locally

```powershell
flutter pub get
flutter run
```

On first launch the app creates a short sample quiz and a sample study topic
in SQLite, along with local demo users for all four roles. Enter the matching
demo email and password manually in the login form: Student
`student@saamep.com` / `password123`, Teacher `teacher@saamep.com` /
`TeacherPass123!`, Parent `parent@saamep.com` / `ParentPass123!`, and Admin
`admin@saamep.com` / `AdminPass123!`. A local first-run administrator account
is also seeded as `jerykan990@gmail.com` / `eyerus@1234`. Demo accounts are
local-only and are not uploaded by cloud sync. Sign-up stores a salted password
verifier; credentials are never stored as plaintext. To enable cloud sign-in,
configure the cloud API below. After a successful online sign-in the
app also caches the account role and a salted password verifier so the same
account can sign in offline on that device.

Student self-registration collects a School ID reference, Grade 8 section, and
gender. New student accounts remain pending until an administrator approves
them; pending, rejected, and blocked students cannot sign in. Teachers may
include assigned subjects during registration. The Admin Panel provides
registration review, parent/student link approvals, teacher temporary-password
resets, exam-performance summaries, and filtered CSV roster export. Admin
account states and database filters are stored in SQLite and survive reloads.

## Cloud API

The mobile client uses a configurable authenticated REST API. Set the API URL
at build/run time; do not hard-code credentials in Dart files:

```powershell
flutter run `
  --dart-define=SAAMEP_API_BASE_URL=https://your-api.example `
  --dart-define=SAAMEP_SUPPORT_EMAIL=help@example.org
```

The API must implement these endpoints:

* `POST /auth/login` accepts `{"email":"...","password":"..."}` and returns
  `{"access_token":"...","user":{"id":"...","email":"...","display_name":"...",`
  `"role":"student|teacher|parent|admin","parent_email":"..."}}`. The parent
  email is optional and is used to link student performance to a parent.
* `POST /sync/{table}` accepts `{"records":[...]}` and idempotently upserts
  records by ID. The client sends users, quizzes, questions, scores, and offline
  study content; it never sends local password verifiers.
* `POST /sync/{table}/delete` accepts `{"records":[{"id":"..."}]}` and
  idempotently deletes records. Local deletions are retained in an outbox until
  the server acknowledges them.
* `GET /sync/{table}?cursor=...` returns
  `{"records":[...],"next_cursor":"..."}`. The initial cursor may be omitted.
  The client persists each table's cursor only after downloaded records are
  merged successfully. The `records` property may also be a bare JSON array.
* `POST /support/feedback` accepts `{"email":"...","message":"..."}`.

Sync requests include the bearer access token received at login. Authenticate
and authorize every endpoint on the server, enforce role permissions there,
validate payloads, and use stable IDs/idempotent operations. Configure the
server so downloads exclude records the signed-in user is not authorized to
read. Sync errors remain visible in the app's Sync Status screen and local
changes are kept for retry.

## Grok explanations

For direct Grok access, configure:

```powershell
flutter run `
  --dart-define=SAAMEP_GROK_API_KEY=your-key `
  --dart-define=SAAMEP_GROK_MODEL=grok-3-mini
```

`SAAMEP_GROK_API_URL` can override the default OpenAI-compatible xAI chat
completions endpoint. A key included in a mobile binary can be extracted.
Production deployments should proxy AI requests through a secured backend
rather than ship a long-lived provider key in the app.

## Offline and role behavior

Students can take cached multiple-choice quizzes with a timer, immediate
feedback, and locally saved scores. Study topics are text-based and available
offline. Teachers can create and manage quizzes/questions and add offline study
topics. Parents see scores for students whose `parent_email` matches their
account and can submit a Student ID linking request for administrator review.
Admins can approve/reject student registrations and parent links, block or
restore access, review platform-wide performance, reset teacher passwords,
export student rosters, manage study content, and request a sync. Dashboard
grade percentages use completed local exam attempts; students without completed
attempts are listed as not assessed rather than counted as failing.
Account roles come from the authenticated user record; the login screen does
not let users choose or elevate their role.
