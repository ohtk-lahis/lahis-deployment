# Publishing experiment results

## 2026-09-09 Native text and lists

Document: https://docs.google.com/document/d/1h7duNVXbEPiqemubE4kxNtQMg0zz8g6gAL_B8Zf6qg8/edit

Input: 02-native-lists.md. Exact successful API batch: 02-native-lists.requests.json.

This is an isolated Google Docs renderer/control experiment, not a successful DOCX import or a completed Markdown publisher. The existing empty trial document was reused. The full guide was not edited.

| Check | Result | Evidence |
|---|---|---|
| Thai text including combining marks | PASS for this fixture | Viewed actual Google Docs editor at 100% in IAB; น้ำ, ผู้ฝึกสอน, เจ้าหน้าที่, พื้นที่ visible |
| Two independent numbered lists | PASS | Both visibly start at 1; API readback gives separate list IDs |
| Wrapped numbered item | PASS | Continuation aligns with item text in editor |
| Wrapped bullet item | PASS | Continuation aligns with item text in editor |
| Native lists rather than typed markers | PASS | API readback contains paragraph.bullet for six items |
| Paragraph spacing | PASS for this fixture | Requested 120% line spacing, 0pt above and 6pt below; editor visually readable |
| DOCX import | NOT VERIFIED | Previous connector import rejected local file references before import |
| Image size and caption grouping | NOT TESTED | Next separate fixture |
| Long tables and page boundaries | NOT TESTED | Next separate fixture |
| Markdown change and complete rebuild | NOT TESTED | Requests captured, but no repeat-build claim |

## Local renderer control

Input: 01-thai.md; builder: build_probe.py. The same DOCX was rendered with the packaged renderer under its default environment and with SAL_FONTPATH=/System/Library/Fonts/Supplemental. Both lost Thai glyphs. System fontconfig finding Tahoma does not prove that the bundled LibreOffice process uses it.

The native experiment uses a different rendering path. It proves that Google Docs can display this fixture; it does not establish the exact cause of the local PDF failure, nor show that the previous chapter DOCX would import correctly.

## Repeat protocol

1. Use an empty disposable document and verify its body before applying the saved batch. Never replay insertText into a populated document.
2. Apply the captured batch once; capture document ID and revision.
3. Read native paragraph styles and list IDs.
4. Open the resulting document in IAB at 100% and inspect rendering there. A local PDF is not a substitute for native editor inspection.
5. Record new results separately when changing font, transport, parser or layout; do not infer untested checks passed.

