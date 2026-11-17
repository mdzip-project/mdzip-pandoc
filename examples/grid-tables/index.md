# Grid tables

This archive carries its own Word reference document, `styles/reference.docx`, named in its manifest:

```json
"pandoc": { "referenceDoc": "styles/reference.docx" }
```

Converted with `docx.lua`, the table below has grid lines and a grey header row. Converted with Pandoc's own Word writer, it has a line under the header only.

| Roast  | Taste          | Grind for   |
|--------|----------------|-------------|
| Light  | Bright, acidic | Pour-over   |
| Medium | Balanced       | Drip        |
| Dark   | Bitter, smoky  | Espresso    |

Every other Word style comes from the reference document too: fonts, headings, page size and margins.
