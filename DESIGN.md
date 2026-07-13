# MacList Actions Design Tokens

Use this system for README media, the interactive project dashboard, and future product previews. HTML surfaces default to Apple/macOS Light Mode; campaign media may use a darker presentation when extra contrast is required.

## Principles

- Calm before clever: one obvious primary action per state.
- Trust is visible: show local-first, human-send, and synthetic-data boundaries near the interaction.
- Spacious and scannable: the first screen shows only the most important status and actions.
- Exact text belongs in code-native assets so filenames, shortcuts, and safety claims remain accurate.
- Content outranks decoration; avoid gradients, neon effects, dense tables, and ornamental motion.

## HTML palette

| Token | Value | Role |
|---|---|---|
| `--canvas` | `#F2F2F7` | Finder-like page background |
| `--surface` | `#FFFFFF` | Window and primary cards |
| `--sidebar` | `#F7F7F9` | Sidebar and quiet grouped regions |
| `--line` | `#D8D8DC` | Borders and dividers |
| `--text` | `#1D1D1F` | Primary text |
| `--muted` | `#6E6E73` | Secondary text |
| `--blue` | `#007AFF` | Single primary/action color |
| `--green` | `#248A3D` | Success status only |

README demo media uses its own high-contrast synthetic scene. Its palette must not be copied into the HTML dashboard.

## Typography

- Interface: system `-apple-system`, with SF Pro on macOS.
- Evidence and commands: SF Mono or `ui-monospace`.
- Use 700 weight for outcomes, 600 for controls, and 400 for supporting text.

## Spacing and shape

- Spacing scale: `4, 8, 12, 16, 24, 32, 48, 72` px.
- Control radius: `10-14` px.
- Panel radius: `20-24` px.
- Use borders before shadows. Avoid decorative gradients and generic feature-card grids.

## Motion

- Demo loop: 12 seconds at 10 frames per second.
- State changes should show query, selection, explicit action, and human-controlled completion.
- Honor reduced-motion preferences in HTML surfaces.

## Media safety

- Use synthetic project names and filenames only.
- Never capture a real desktop, account, chat, email address, recipient, or filesystem path.
- Label every demo `SYNTHETIC DEMO · NO PERSONAL DATA`.
