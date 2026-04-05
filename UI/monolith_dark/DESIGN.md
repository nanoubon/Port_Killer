```markdown
# Design System Specification: Port Killer

## 1. Overview & Creative North Star
**The Creative North Star: "The Precise Instrument"**

This design system is engineered to feel like a high-performance surgical tool for developers. It moves beyond standard macOS utilities by embracing an "Editorial Technical" aesthetic. We reject the "boxed-in" look of traditional enterprise software. Instead, we use a sophisticated interplay of deep tonal layering, intentional asymmetry, and extreme typographic hierarchy to create an environment that feels both authoritative and breathable. 

The experience is defined by "The Quiet Power"—where the UI recedes into the background until an action is required, allowing technical data to take center stage through crisp, monospace clarity and glass-like surfaces.

---

## 2. Colors & Surface Philosophy
The palette is rooted in a deep-space charcoal base, punctuated by high-signal accents that guide the eye to critical system states.

### Surface Hierarchy & Nesting (The "No-Line" Rule)
We prohibit the use of 1px solid borders for sectioning. Structural definition is achieved exclusively through **Tonal Layering**.
- **Base Layer:** The application window uses `surface` (#131313).
- **Secondary Sections:** Sidebars or utility panels use `surface_container_low` (#1C1B1B).
- **Floating Elements:** Modals or popovers use `surface_bright` (#393939) with a 20px backdrop blur to create a "frosted obsidian" effect.
- **The Glass Rule:** For toolbars and sidebars, use `surface` at 80% opacity with a `saturate(180%)` and `blur(30px)` filter. This allows desktop wallpapers to bleed through subtly, grounding the app in the macOS environment.

### Accent Strategy
- **Primary Action (Blue):** Use `primary` (#AAC7FF) for active selections and focus states.
- **Positive Status (Green):** Use `secondary` (#47E266) for active ports.
- **Warning (Yellow):** Use `tertiary_fixed` (#FFDAD5) for high-resource usage warnings.
- **Destructive (Red):** Use `error` (#FFB4AB) strictly for the "Kill" action.

---

## 3. Typography: The Technical Editorial
We utilize a dual-font strategy to balance premium aesthetics with raw data legibility.

| Level | Token | Font Family | Size | Weight/Note |
| :--- | :--- | :--- | :--- | :--- |
| **Display** | `display-md` | Inter / SF Pro | 2.75rem | Tight tracking (-2%) for headers. |
| **Headline** | `headline-sm` | Inter / SF Pro | 1.5rem | Medium; for view titles. |
| **Technical Data**| `title-sm` | JetBrains Mono | 1.0rem | For PIDs, Port numbers, and Hex codes. |
| **Body** | `body-md` | Inter / SF Pro | 0.875rem | For descriptions and metadata. |
| **Label** | `label-md` | Space Grotesk | 0.75rem | All-caps, 5% letter spacing for "utility" labels. |

**Editorial Intent:** Use `display-md` for empty states or "Zero-Port" dashboards to create a bold, confident brand moment. Technical data must always use monospace tokens to ensure column alignment in lists.

---

## 4. Elevation & Depth
Depth is a functional cue, not just an aesthetic choice. We use **Tonal Stacking** to signify hierarchy.

*   **Ambient Shadows:** For floating utility panels, use a shadow with `blur: 40px`, `y: 20px`, and color `surface_container_lowest` at 40% opacity. This creates a soft, natural lift.
*   **The Layering Principle:** An inner list item should be `surface_container_high` sitting on a `surface_container` background. This "paper-on-paper" look is more sophisticated than a bordered box.
*   **The Ghost Border:** In high-density data views where tonal shifts aren't enough, use a 1px stroke of `outline_variant` at **15% opacity**. It should be felt, not seen.

---

## 5. Components

### Buttons
*   **Primary (Kill Action):** Background `error_container`, text `on_error_container`. Roundedness `lg` (0.5rem).
*   **Secondary (Active/Blue):** Background `primary_container`, text `on_primary_container`.
*   **Ghost (Default):** No background. Text `on_surface_variant`. Subtle `surface_bright` fill on hover.

### Process Cards & Lists
*   **The "No Divider" Rule:** Forbid 1px dividers between list items. Use 12px of vertical padding and a subtle `surface_container_low` hover state to define rows.
*   **Micro-Signals:** Use a 4px vertical pill of `secondary` (#47E266) on the far left of a list item to indicate a process is currently "Listening."

### Input Fields (Terminal Style)
*   **Styling:** Background `surface_container_lowest`, no border. 
*   **Focus State:** A subtle outer glow using `primary` at 20% opacity. Use Monospace font for the input text to match the developer's mental model.

### Specialized Component: The "Port Heatmap"
A custom visualization using small 8px `xl` rounded squares. Colors transition from `secondary` (Idle) to `tertiary_container` (High Traffic) to represent port activity levels.

---

## 6. Do's and Don'ts

### Do
*   **DO** use whitespace as a separator. If a layout feels cluttered, increase the gap before adding a line.
*   **DO** use Monospace for any string of numbers (PIDs, Ports, Memory).
*   **DO** use `surface_tint` at 5% opacity overlays to "warm up" or "cool down" different functional zones of the app.

### Don't
*   **DON'T** use 100% white (#FFFFFF) for text. Use `on_surface` (#E5E2E1) to reduce eye strain in dark mode.
*   **DON'T** use standard macOS "System Blue" if a `primary` token is available. Our blues are curated for deep charcoal backgrounds.
*   **DON'T** use heavy drop shadows. If an element needs to pop, increase its `surface_container` tier instead.
*   **DON'T** use 90-degree corners. Everything must adhere to the `md` (0.375rem) or `lg` (0.5rem) roundedness scale to maintain the "Native macOS" feel.

---

## 7. Interaction Micro-interactions
*   **State Transitions:** All hover states should have a 200ms ease-out transition.
*   **The "Kill" Feedback:** When a port is killed, the row should collapse with a spring animation (`damping: 20`, `stiffness: 150`) rather than simply vanishing.
*   **Glass Flickers:** Tooltips should fade in with a slight backdrop-blur increase, mimicking the way physical glass catches light.