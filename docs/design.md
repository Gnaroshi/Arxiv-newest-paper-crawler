# macOS design contract

## Screen purpose

The main window answers five questions without opening another screen: what the app finds, whether discovery is ready or running, which time window is active, how many papers are visible, and what action is available next.

## Layout

- Sidebar: Calendar, Inbox, New, Saved, Reviewed, All, Cleanup, Trash, collections, editable research topics, and observed subject filters.
- Candidate column: status, bounded time-window control, search, and paper rows.
- Detail column: one selected paper with metadata, abstract, and explicit actions.
- Settings: Gemini key and model information separated from data-folder commands.
- Calendar has an explicit collection scope: research topics (default VLA + World Models) or broad arXiv subject tags. Topic browsing in the sidebar and the remote collection scope are distinct controls.
- Cleanup presents counts, a preview list, protected work, and a single recoverable apply action. Trash holds removed metadata outside the live paper array, with individual restore and last-batch undo. Permanent metadata removal is a separate confirmed action; it never removes downloaded PDFs or reading notes.
- Research topics are searchable, editable OR phrases with optional AND/NOT conditions. Remote discovery and local filtering use the same title/abstract rules. Dates only bound the search; category-wide collection is explicitly separate and warns about unrelated results.
- English is the interface language. Korean is reserved for requested abstract translations, not navigation or action labels.
- Bookmark means Save for later, checkmark means Mark reviewed, trash means Remove from the library. Review and save are independent; neither clears collections or notes. All icon controls have help and an accessible action name.

The minimum window is 900×620. Text wraps before controls compress. The candidate and detail columns remain independently scrollable.
Calendar and Cleanup use the full workspace instead of an empty detail placeholder. Calendar search actions stay pinned below the scrollable dates; date-by-date progress, cancellation and errors appear beside those actions.

## Performance and recovery

Topic evidence and normalized searchable text are indexed when papers or rules change, not during SwiftUI row rendering. Search is debounced by 150 ms. Sidebar counts are cached. Trash is loaded on demand, and archive writes run off the UI thread with one mutation at a time. Cleanup archives metadata and a pre-change backup before compacting the live array; tombstones prevent deleted papers from silently reappearing during discovery.

## Shared application language

Uses the Gnaroshi native application/UI guidance: system typography, SF Symbols, quiet full-width work surfaces, semantic status colors, consistent action spacing, and progressive disclosure. The sky role accent remains specific to Arxiv Discovery; PaperFlow's older gradient/card-heavy layout is not copied. There is no custom browser UI or local web server.

## Visual grammar

- Use system typography and SF Symbols.
- Use the shared near-black/charcoal surfaces in dark mode and complete system-adaptive light surfaces in light mode.
- Use Arxiv sky `#82C7EE` for application identity and selection, never for success or failure semantics.
- Use square 4–8 px geometry, two-pixel selected markers, and at most one short hard-edged primary-action shadow.
- Avoid card nesting, gradients, glass blur, decorative badges, and motion that does not communicate state.

## Accessibility

- Every icon-only button has an accessibility label and help text.
- Status has text in addition to color and icon.
- Keyboard selection, search, multi-date discovery, review, save, collection, note, translate, and PDF actions remain available.
- Reduced motion changes no meaning because the interface uses no required animation.
