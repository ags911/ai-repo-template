import { expect, test, type Page, type TestInfo } from "@playwright/test"

// Look at it. Captures every state of the UI at a desktop and a phone width into the test
// output folder (open the images and read them: see .agents/skills/ui-review), and runs
// layout guards on each. A test that passes and an axe scan that finds nothing do not show
// that the page looks right. Add a state for every new screen, dialog section or error.
// Do not loosen a guard to make a state pass; fix the layout.
//
// Fill in STATES. Each `setup` drives the page to that state; baseURL comes from your
// Playwright config. Adjust the selectors in `layoutProblems` to your design system's slots.

const VIEWPORTS = [
  { name: "desktop", width: 1280, height: 900 },
  { name: "phone", width: 390, height: 844 },
] as const

type State = { name: string; setup: (page: Page) => Promise<void> }

const STATES: State[] = [
  { name: "home", setup: async (page) => { await page.goto("/") } },
  // { name: "form-error", setup: async (page) => { ... } },
]

/** Layout rules that hold for every state. Returns what is wrong, in words. */
async function layoutProblems(page: Page): Promise<string[]> {
  return page.evaluate(() => {
    const out: string[] = []
    const visible = (el: Element) => {
      const r = el.getBoundingClientRect()
      const s = getComputedStyle(el)
      return r.width > 0 && r.height > 0 && s.visibility !== "hidden" && s.display !== "none"
    }
    const name = (el: Element) =>
      el.getAttribute("aria-label") || el.textContent?.trim().slice(0, 32) || el.id || el.tagName.toLowerCase()

    // 1. Nothing makes the page scroll sideways.
    const root = document.documentElement
    if (root.scrollWidth > root.clientWidth + 1) out.push(`the page scrolls sideways (${root.scrollWidth}px in ${root.clientWidth}px)`)

    // 2. Every control is a reasonable target (WCAG 2.2 minimum, 24 by 24 px).
    const controls = 'button, [role="button"], [role="combobox"], [role="switch"], input:not([type="hidden"]), textarea, select'
    for (const el of document.querySelectorAll<HTMLElement>(controls)) {
      if (!visible(el)) continue
      // A control inside a <label> is clicked through the label, so the label is the target
      // (WCAG 2.5.8 counts the whole clickable area). This assumes a native <label> that
      // activates the control; a styled <div> that only looks like a label does not count.
      const r = (el.closest("label") ?? el).getBoundingClientRect()
      if (r.width < 24 || r.height < 24) out.push(`"${name(el)}" is ${Math.round(r.width)}x${Math.round(r.height)}px, under 24px`)
    }

    // 3. Text never touches the edge of the control that holds it.
    const padded = 'button, [role="button"], [role="combobox"], input:not([type="hidden"]), textarea, select'
    for (const el of document.querySelectorAll<HTMLElement>(padded)) {
      const hasText = Boolean(el.textContent?.trim()) || el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement
      if (!visible(el) || !hasText) continue
      const s = getComputedStyle(el)
      const left = parseFloat(s.paddingLeft)
      const right = parseFloat(s.paddingRight)
      if (left < 8 || right < 8) out.push(`"${name(el)}" has ${left}px / ${right}px side padding, under 8px`)
    }
    return out
  })
}

for (const viewport of VIEWPORTS) {
  test.describe(`screens at ${viewport.name} (${viewport.width}px)`, () => {
    test.use({ viewport: { width: viewport.width, height: viewport.height } })
    for (const state of STATES) {
      test(state.name, async ({ page }, testInfo: TestInfo) => {
        await state.setup(page)
        await page.waitForTimeout(500) // let animations settle before the picture
        await page.screenshot({ path: testInfo.outputPath(`${state.name}-${viewport.name}.png`) })
        expect(await layoutProblems(page), `${state.name} at ${viewport.name}`).toEqual([])
      })
    }
  })
}
