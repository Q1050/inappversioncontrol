## 0.0.5

* Added the public `SupabaseVersionRuleProvider` with environment, platform,
  custom schema, custom column, and custom row-mapping support.
* Added `iavc app:supabase configure` to initialize Supabase, generate a
  read-only version-rule migration, and optionally deploy it to a linked project.
* Added Supabase provider and CLI tests plus a credential-free example flow.
* Reworked the README opening with a faster quick start and complete Firebase,
  Supabase, and custom-backend setup guidance.

## 0.0.4

* Added opt-in lifecycle-aware policy checks with one recheck per genuine app
  resume cycle.
* Added deterministic check coalescing to prevent overlapping provider calls.
* Preserved the last successful policy decision when a later refresh fails.
* Added Dartdoc comments across the public API to make package setup and usage
  easier to discover in editors and generated documentation.

## 0.0.1

* Added optional, forced, and maintenance update decisions.
* Added platform and deployment-environment rule selection.
* Added Firebase Remote Config and custom HTTP endpoint providers.
* Added the `iavc` CLI for rule validation, endpoint testing, and Firebase setup.
