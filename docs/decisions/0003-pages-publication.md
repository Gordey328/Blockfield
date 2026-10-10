# ADR 0003: Pages branch publication while Actions is unavailable

Date: 2026-10-10. Status: temporary operational adaptation.

GitHub Actions run 38031633237 on source commit 5d367df failed before starting
any steps. The check annotation states: "The job was not started because your
account is locked due to a billing issue." This is an account condition, not a
Godot build failure. No billing or payment settings were changed.

Build and validate locally using the same pinned engine/scripts. Publish the
complete generated bundle, licenses and source-commit metadata in `gh-pages`.
Configure Pages with `build_type=legacy`, source `gh-pages:/`, and request a
Pages build. `tools/publish_pages.py` provides the repeatable publication path.
Verification of a queued request alone is not proof that the site is live.

The custom workflow remains available for future automation. Restoring it needs
the account's Actions availability restored and Pages switched back to workflow
hosting. Source stays on `main`; generated engine files stay on `gh-pages`.
