# ADR-0001: No Browser Bookmark Sync

## Status

Accepted

## Context

Feature request: Import/export browser bookmarks per context.

Use case: When switching browsers or setting up a new context, import existing bookmarks automatically.

### Technical Analysis

- **Netscape Bookmark HTML** is the universal exchange format (all browsers support it)
- Chrome/Edge/Brave: `--import-bookmarks-from=<file>` works only on first profile launch
- Firefox: No CLI import option
- Export: Would need to parse `Default/Bookmarks` (JSON) or `places.sqlite` (Firefox)

### Complexity

1. Browser-specific import/export logic
2. Conflict with existing `bm` command (URL aliases vs browser bookmarks)
3. Import only works on empty profile (re-import = manual)
4. Would need to handle `rename` (move bookmark files) and `export/import` (zip config dir)

## Decision

**Do not implement browser bookmark sync.**

Reasons:

1. **Scope creep**: `browser-contexts` focuses on session isolation + quick access, not browser management
2. **Existing `bm` command**: Covers the 80% use case (2-3 daily-driver URLs per context)
3. **Better alternatives**: Full link collections belong in versioned workspace docs (`links.md`)

| Approach | Versioned | Team-shared | Notes/Context | Quick CLI Access |
|----------|-----------|-------------|---------------|------------------|
| `bc bm` (config) | ❌ | ❌ | ❌ | ✅ |
| `links.md` in workspace | ✅ | ✅ | ✅ | ❌ |
| Browser bookmarks | ❌ | ❌ (unless sync) | ❌ | ❌ |

## Consequences

- Keep `bm` command as lightweight URL alias feature
- Users manage comprehensive link collections in workspace repos
- Less code, clearer scope
