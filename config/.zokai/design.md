# Zokai Station Design System & Handoff Spec

> **Purpose:** This file documents the visual "DNA" of the Zokai Station dashboard. It serves as the single source of truth for generating new UI components (like the Kanban Board) via visual prototype agents (Stitch MCP).

## The 3-Step Prototype-First Workflow

This workflow replaces the traditional "code it from scratch" approach by injecting a visual review gate before any project files are touched. 

### Step 1 — Ask Stitch MCP for the visual shape

Load the design tokens (below) into context and call the Stitch MCP. Use a prompt similar to this:

```text
Design a Kanban board panel for a VS Code-style dark dashboard.
Design language:
- Background: #12141e, panels: #1a1c29, borders: #2a2d3e
- Text: #d4d4d4, muted: #7a7e9a, accent: #4d98f0
- Font: Inter 14px, border-radius: 8px on cards, 4px on badges
- Cards: bg=#1a1c29, border=1px solid rgba(255,255,255,0.05)
- No drop shadows except subtle on hover (translateY -1px)
- 4 columns: Backlog / In Progress / Review / Done
- Each column header: uppercase 10px muted label + count badge
- Cards: title (13px), labels as colored pills (same as ideas-filter-chip style), priority dot
- No drag-drop needed yet — static layout only
Output: HTML + CSS snippet
```

*Value: Stitch generates a coherent visual prototype matching the existing aesthetic that you can review visually.*

### Step 2 — Extract and Integrate

Once the visual prototype is approved, pass the artifact to Kilo (or Antigravity) to wire it in:
1. **Strip hardcoded CSS**: Replace all hardcoded hex colors from the Stitch output with the CSS variables defined below (e.g., `#1a1c29` becomes `var(--vsc-sidebar)`).
2. **Create the module**: Create `core/config/dashboard/[component].js` (e.g., `kanban.js`).
3. **Wire data**: Connect the UI to the appropriate data source (e.g., mcp-tasks API).
4. **Wire routing**: Add tab activation logic to `app.js` (following the existing pattern from the Ideas Board).
5. **Merge CSS**: Add the cleaned CSS to `dashboard.css` under a dedicated comment block.

### Step 3 — Verify Coherence

Review the new component code side-by-side with existing components (like `ideas.js`) to ensure behavioral consistency:
- Same card hover pattern (`translateY(-1px)`, same transition timing).
- Same header structure (uppercase 10px muted + count).
- Same filter chip style.
- Same modal style if applicable.
## Design Tokens (The DNA)

These values map directly to variables defined in `core/config/dashboard/dashboard.css`. When generating prototypes, use these hex values to ensure the agent produces matching aesthetics, then swap them for the `--vsc-*` variables during integration.

### Colors
- **Background (`--vsc-bg`)**: `#12141e` (Main application background)
- **Panel/Sidebar (`--vsc-sidebar`)**: `#1a1c29` (Card backgrounds, sidebars, modals)
- **Border (`--vsc-border`)**: `#2a2d3e` (Subtle dividers)
- **Text (`--vsc-text`)**: `#d4d4d4` (Primary text, very readable off-white)
- **Muted Text (`--vsc-muted`)**: `#7a7e9a` (Secondary text, dates, column headers)
- **Accent/Blue (`--vsc-accent`)**: `#4d98f0` (Primary buttons, active states, highlights)

### Status Colors (Badges/Labels)
- **Green (`--vsc-green`)**: `#4ec9a0` (Done, Success)
- **Amber (`--vsc-amber`)**: `#ce9178` (In Progress, Warning)
- **Red (`--vsc-red`)**: `#f47070` (Blocked, Error)
- **Purple (`--vsc-purple`)**: `#c586c0` (Review, Special)

### Typography
- **Font Family**: `Inter, system-ui, sans-serif`
- **Standard Sizes**:
  - Base text: `13px` or `14px`
  - Small/Muted labels: `10px` or `11px` uppercase
  - Headings: `16px` to `20px`

### Component Styles
- **Cards**:
  - Background: Panel color (`#1a1c29`)
  - Border: `1px solid rgba(255, 255, 255, 0.05)`
  - Border Radius: `8px`
  - Hover State: No drop shadows. Use subtle translation: `transform: translateY(-1px)` with smooth transition.
- **Badges/Chips**:
  - Border Radius: `4px` or fully rounded (`999px`)
  - Padding: Typically `2px 6px` or `4px 8px`
  - Background: Usually a 10-15% opacity version of the status color.

## Kanban Board Specific Constraints
When generating the Kanban board:
1. 4 columns: Backlog, In Progress, Review, Done.
2. Column headers should be uppercase, muted text (10px) with a count badge.
3. Cards need to support a title, label pills, and a priority indicator.
4. Keep the layout static for the prototype (no drag-and-drop JS).
