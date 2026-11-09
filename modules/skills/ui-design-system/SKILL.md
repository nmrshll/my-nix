---
name: framework-agnostic-ui-design-system
description: Use when building, reviewing, or refactoring user interfaces. Prevents “AI slop” by enforcing component-level separation, design-system reuse, composition, and layout abstraction across any language, framework, or styling system.
---

# Framework-Agnostic UI Design System Skill

## When to use
Use this skill whenever an agent is:
- vibe-coding a UI
- adding or changing components
- reviewing UI code for maintainability
- refactoring inconsistent styles
- deciding whether to create a new component
- adapting a design system across frameworks

## Core model: four component levels
1. **Headless / primitive components**
   - Handle behavior, accessibility, DOM/positioning, keyboard and touch support, mobile adaptation.
   - Unstyled or minimally styled.
   - May have complex APIs.
   - Examples: headless menu, dialog, popover, combobox.

2. **Design-system components**
   - Wrap primitives and add consistent styling, tokens, variants, sizes, states.
   - Form the reusable UI vocabulary: buttons, cards, inputs, badges, alerts.
   - Should be reused everywhere.

3. **Layout components**
   - Abstract common page/app layouts: shells, stacks, grids, sidebars, toolbars, panels.
   - Optional, but useful for maintainability and readability.
   - Do not over-extract too early.

4. **Consumer / feature components**
   - Build actual screens by composing design-system and layout components.
   - Should not invent new visual primitives.
   - If a new reusable visual pattern appears here, promote it to the design system.

## Minimal rules
1. **Start from the best available design-system architecture.**
   - If using React + Tailwind, prefer shadcn/ui unless there is a strong reason not to.
   - In other stacks, use the established equivalent: headless primitives + a consistent design-system layer.
   - Do not hand-roll everything unless necessary.

2. **Customize styling through the design system, not through one-off overrides.**
   - Use themes, tokens, presets, variants, sizes, and official generators when available.
   - Avoid scattering raw `className`, `style`, or ad-hoc CSS across consumer components.
   - If a novice is involved, prefer official theme/preset tools over manual invention.

3. **Modifying design-system component source is allowed only intentionally.**
   - Copy-paste design systems like shadcn/ui expect and encourage this.
   - Keep modifications consistent and reusable.
   - Do not fork a component silently in a feature file.

4. **Keep component levels separate.**
   - Design-system components: e.g. `components/ui` or equivalent.
   - Layout components: e.g. `components/layout` or equivalent.
   - Consumer components: keep inside feature/page modules.
   - If a new styled button appears inside a feature, write it as a design-system component and reuse it.

5. **Compose before styling.**
   - Prefer provided composition patterns over raw `div` + flex/grid.
   - Prefer props like `variant`, `size`, `state`, `tone` before writing custom CSS.
   - If creating new design-system components, give them out-of-the-box composition APIs and variants.
   - Have agents mimic the chosen design system’s existing patterns.

## Cross-framework adaptation
The principles do not depend on React, Tailwind, or shadcn/ui.

- **React / Tailwind:** shadcn/ui is the default reference.
- **Vue / Svelte / Solid / Angular / etc.:** use equivalent headless primitives and design-system libraries.
- **CSS approach:** Tailwind, CSS Modules, styled-components, vanilla CSS, etc. — still use tokens, variants, composition, and separation.
- **Any language or templating system:** apply the same four levels at the component/widget/template level.
- **No component framework:** create the same discipline with templates, partials, macros, or widgets.

## Workflow
1. Identify the stack and any existing design system.
2. Classify the requested UI work by component level.
3. Reuse existing level 2 and level 3 components first.
4. If something is missing, add it at the correct level — not in the consumer component.
5. Use variants, sizes, tokens, and composition APIs before raw styling.
6. Extract layout components only when repetition or readability justifies it.
7. Review for slop:
   - duplicate buttons
   - ad-hoc flex/grid everywhere
   - inconsistent spacing, color, radius, typography
   - inaccessible primitives
   - missing mobile/touch behavior
   - one-off styles in feature code
8. Refactor toward the design-system vocabulary.

## Guardrails
- Do not create a new visual style inside a page or feature component.
- Do not bypass accessibility or behavior primitives.
- Do not use raw layout styling when a composition component exists.
- Do not over-abstract layouts prematurely.
- Do keep code readable and maintainable.
- Do let agents mimic the chosen design system’s patterns.
- Do promote repeated one-offs into reusable design-system components.

## Expected agent behavior
When implementing or reviewing UI, the agent should:
- state which component level each piece belongs to
- reuse existing design-system components and variants
- add new design-system components only when needed
- provide composition-friendly APIs for new components
- avoid framework-specific assumptions unless the project already uses them
