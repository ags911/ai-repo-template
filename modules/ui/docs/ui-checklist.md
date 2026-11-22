# UI checklist

Used by `ui-review` and by anyone reviewing a UI change. Tick each item for every captured
state, at desktop and phone width. "Guard" marks what `screens.spec.ts` already enforces.

## Spacing and alignment
- Every button, select and field has visible padding; text never touches the control's edge. (guard)
- Controls in one row sit together. A primary action is not stranded at the far side of a wide row. (guard)
- Heights and widths of like controls match (all selects in a form share one width).
- Spacing between groups is larger than spacing inside a group.
- Nothing overlaps, clips or scrolls sideways. (guard)

## Targets and focus
- Every control is at least 24 by 24 px (prefer 44 px on touch layouts). (guard)
- Focus is visible on every control, and tab order follows reading order.
- A dialog or drawer traps focus, closes on Escape, and returns focus to what opened it.

## States
Check each of these exists and looks intentional, not just the happy path:
- empty, loading, success, error (with what to do next), disabled (visibly different), and
  a case with long text or many items.
- The same fact is not shown twice, and two messages on screen never contradict each other.

## Readability
- Text contrast is at least 4.5:1, and 3:1 for large text and control borders.
- Secondary text is still readable at its size; no important text is below 12 px.
- Error and status messages say what happened and what the person can do.

## Responsive
- At 390 px wide nothing needs sideways scrolling, and drawers and dialogs use the full width.
- Rows that sit side by side on desktop stack cleanly on a phone.

## Consistency and CSS pitfalls
- Spacing, colours and radii come from the design system's tokens, not one-off values.
- Global resets and element selectors are in a cascade layer below the utilities (or absent):
  an unlayered `* { padding: 0 }` silently removes padding from every utility class.
- A change to a shared component is checked on every screen that uses it.
