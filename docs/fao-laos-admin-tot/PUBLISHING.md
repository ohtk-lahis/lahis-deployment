# Publishing and maintaining the Google Doc

## Source of truth

Keep the chapter files in `chapters/`, [BOOK.md](./BOOK.md), and the approved crops or diagrams in `screenshots/` as the source of truth. The online document is a generated shared reading and review copy.

Current online draft: [LAHIS Admin Train the Trainer Guide FAO Laos](https://docs.google.com/document/d/1fQ5PPBGFqQBeDZBfwNpIxYhvlCGDEjS1WU_erig-j_o/edit).

## Reader order and source format

[BOOK.md](./BOOK.md) defines reader order. [MARKDOWN_CONTRACT.md](./MARKDOWN_CONTRACT.md) defines the only supported source blocks and the reader-build rules. This order is intentional: the Case workflow gives context before the separate System Admin Case Definition, Case close form, and Reporter Alert chapters.

## Normal update process

1. Update the relevant Markdown chapter first, following the source contract. Add or replace an image only when it teaches the point being discussed; crop the interface to that point.
2. Review the chapter against Staging or Production as appropriate, without changing production data during verification. Record the result in `STATUS.md`.
3. Run the source validation in the contract, then regenerate and visually review a reader document from the Markdown source. Do not repair headings, lists, page breaks, or captions directly in Google Docs as the normal process.
4. Publish the reviewed build as a new edition, or replace the shared copy only through a reproducible build process. Decide which option is appropriate with the document owner.

For wording proposed directly by reviewers in Google Docs, accept it in Markdown first, then rebuild the reader copy. This prevents the online copy and the repository source from drifting apart.

## Sharing

The online draft is created in the owner's Google Drive and is not made public automatically. The owner can use **Share** in Google Docs to invite named reviewers as `Commenter` or `Editor`; use `Viewer` for readers who should not change the guide. Decide separately before enabling an anyone-with-the-link setting.
