---
name: research
description: Investigate or verify facts, sources, data availability, or methodological evidence for the cs2-brt research project. Use for research legwork and source validation; do not use for ordinary code implementation or analysis runs using already-collected data.
---

Before researching, follow the research startup and source-of-truth rules in the repository's `AGENTS.md`: read the required overview and decision-log documents, then the canonical documents and existing `docs/research/` notes relevant to the question. Identify the existing owner of the topic and any material conflict before proceeding.

## Agree on the artifact

Resolve the output before dispatching research:

- If the user already requested a file or a chat-only answer, treat that as the decision. When saving, state the planned path before starting.
- Otherwise, ask whether to create or update a Markdown research note. Recommend saving for ordinary research and show the planned path in the same question. Recommend chat-only only for a simple local fact check.
- Prefer updating an existing note that owns the same topic. For a new standalone reference investigation, use `docs/research/` and match its naming convention.

Wait for the user's answer when a choice is required.

## Delegate the research

After the artifact decision, always dispatch a background agent. Give it the research question, the required repository context, the applicable canonical documents, and the agreed output mode. The background agent investigates and returns its findings and, when needed, a Markdown draft to the main agent; it does not edit repository files.

The background agent must:

1. Prefer sources that own the claim: issuing bodies' materials, official documentation, specifications, source code, first-party APIs, original methodological papers, local actual data, and facts explicitly confirmed by the user.
2. Search for a primary source before relying on a secondary source. When only a secondary source is available, identify it as secondary and mark the affected claim as provisional or unconfirmed.
3. Put a descriptive Markdown source link near each supported claim and distinguish sourced facts from inference.
4. Compare findings with the applicable canonical documents and active decisions. Report material conflicts instead of resolving them silently.

## Review and deliver

The main agent reviews the returned findings against the repository's source-of-truth hierarchy before writing or answering.

- Use one Markdown file per research task unless the user explicitly requests otherwise.
- A research note must include a title, research date, scope, positioning, conclusion, source links near the relevant claims, and unresolved or unconfirmed points.
- Avoid duplicating details owned by canonical documents; summarize only what the note needs and link to the owner.
- Approval to create or update a research note does not authorize changes to canonical documents or decision logs. Present those proposed changes separately and obtain explicit approval before applying them.
- When the user chose chat-only, return the same evidence status, citations, conflicts, and unresolved points in the response.

The research is complete when every question is answered or explicitly marked unresolved, every factual claim has an appropriate source and evidence status, the agreed artifact choice is honored, and no canonical research decision has been changed without explicit approval.
