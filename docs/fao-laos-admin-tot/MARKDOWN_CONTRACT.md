# Markdown source contract

This contract keeps the Markdown chapters suitable for a deterministic reader build. The Markdown files and approved assets are the source of truth; Google Docs is a generated shared copy, not a second authoring format.

## 1. Book structure

- [BOOK.md](./BOOK.md) is the single source for chapter number, title, and reader order. A build must never use filename order as the table of contents.
- Every chapter begins with exactly this front-matter shape:

  ```yaml
  ---
  unit: uNN
  chapter: "N" # or "N.N"
  title: "Reader-facing title"
  status: draft | reviewed
  staging_checked: not-required | not-yet | partial | YYYY-MM-DD
  ---
  ```

- Every chapter contains one H1 only, in the form `# {chapter} {title}`. It must match the chapter row in `BOOK.md`.
- `##` is a main lesson section and `###` is a named subtopic. Do not put step numbers in headings; use an ordered list for a sequence of actions.
- The table of contents appears only in `BOOK.md` and is generated from that manifest in a reader build. Chapters must not keep a copied or shortened contents table.

## 2. Allowed reader blocks

| Need | Markdown form | Build result |
|---|---|---|
| Narrative | ordinary paragraph | ordinary paragraph |
| Action sequence | direct ordered list (`1.`, `2.`, ...) | one local native numbered list |
| Non-sequential points | direct bullet list (`-`) | one native bullet list |
| Compare, check, or map fields | GFM table | native table |
| Caution or trainer guidance | `###` named heading followed by direct bullets | heading plus native bullet list |
| Screenshot or diagram | image line followed immediately by italic caption | anchored figure and caption |
| Literal system input or template | fenced code block with a language | monospace code block |

Use named headings such as `### ข้อควรปฏิบัติ`, `### ข้อควรหลีกเลี่ยง`, `### ข้อควรระวัง`, and `### ประเด็นที่ใช้พูด`. These headings replace blockquotes.

## 3. Prohibited source forms

- No blockquote-led layout (`>`), including `> -` pseudo-bullets.
- No ASCII arrows, box diagrams, or visual flows in code fences. Write a short ordered list under a named section instead.
- No raw dash prefix used as body text. A dash means a real native bullet list.
- No duplicate or manually maintained table of contents in a chapter.
- The chapter body is reader-facing content only. Do not include author prompts, production notes, workshop schedules, image inventories, asset filenames, or screenshot TODOs.
- Do not add headings such as `ลำดับเนื้อหาของเล่ม`, `ภาพประกอบที่ใช้สอน`, `สคริปต์อบรม`, or `สคริปต์เล่า`. Keep book order in `BOOK.md`, asset work in `STATUS.md`, and facilitation plans outside the reader manuscript.
- No reader-facing `<!-- Screenshot pending -->` comments. Track missing screenshots in `STATUS.md` instead.
- No instruction to change an online Google Doc by hand as the normal publishing path.

## 4. Images and captions

- Use only approved crops in `screenshots/`; crop to the control or state being explained and remove unrelated controls or personal data.
- Place the image directly after the paragraph or list it supports. Place an italic caption immediately below it.
- A screenshot documents visible UI state only. Do not use it as proof of persistence, authorization, or a production configuration.
- If no image is ready, keep the lesson text complete and record the missing asset in `STATUS.md`.

## 5. Check table

- Each chapter ends with `## Check` and one two-column table: `ผู้ฝึกสอนควรสามารถ` and `วิธีตรวจ`.
- A check must be demonstrable from the chapter itself. Do not use generic rows such as `รู้ขอบเขตของบทนี้`.

## 6. Reader-build contract

The reader build must:

1. Assemble chapters in `BOOK.md` order and create the table of contents from the same rows.
2. Preserve headings, tables, and figure-caption pairs as semantic blocks.
3. Convert every Markdown list into a separate native Google Docs list, restarting at `1` for each ordered list.
4. Keep a heading with the first paragraph or list that follows it, and keep a figure with its caption where the renderer supports it. It may move the whole group to the next page; it must not split a short group unnecessarily.
5. Render each draft to pages and review page breaks, bullets, figures, and captions before publishing.

## 7. Source validation before a rebuild

Before regenerating the Google Doc, verify:

1. every manifest source exists once and every chapter belongs to the manifest;
2. front matter and H1 match the manifest;
3. no chapter contains a blockquote or a visual flow in a code fence;
4. every image reference resolves to an approved asset;
5. no reader body contains editorial headings, asset inventories, screenshot status, or author TODOs;
6. every chapter ends with a valid `Check` table; and
7. `git diff --check` is clean.
