# macOS design contract

## Screen purpose

The main window answers five questions without opening another screen: what the app finds, whether discovery is ready or running, which time window is active, how many papers are visible, and what action is available next.

## Layout

- Sidebar: Calendar, Inbox, New, Saved, Reviewed, All, collections, VLA/World Models, and observed subject filters.
- Candidate column: status, bounded time-window control, search, and paper rows.
- Detail column: one selected paper with metadata, abstract, and explicit actions.
- Settings: Gemini key and model information separated from data-folder commands.

The minimum window is 900×620. Text wraps before controls compress. The candidate and detail columns remain independently scrollable.

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
