# IEEE JSTARS version

This folder holds the LaTeX version of the [draft paper](../manuscript.md) for
the IEEE Journal of Selected Topics in Applied Earth Observations and Remote
Sensing (JSTARS). It is generated from the markdown by
[paper_to_ieee.py](../../scripts/paper_to_ieee.py) and is the starting point for
editing on Overleaf.

- [main.tex](main.tex): the manuscript in the IEEEtran journal class.
- [supplement.tex](supplement.tex): the supplement, submitted as a separate
  PDF.
- [references.bib](references.bib): an IEEE copy of the
  [bibliography](../../docs/references.bib).

The figures are read from [../figures](../figures/), so they are not copied
here: a figure's PDF where there is one beside its PNG, otherwise the PNG.

## What the conversion changes

- The highlights are dropped, and any "the highlights," left in the main text
  is removed with them. The keywords become IEEE Index Terms in
  alphabetical order, and headings take IEEE headline style ("Related Work")
  in both documents; the last section is "Conclusion", singular, as in IEEE
  journals.
- Sections are numbered I, II and so on, and subsections A, B and so on. Every
  reference to a manuscript section, table or figure is a `\ref`, so Section
  4.2 of the markdown prints as Section IV-B, Table 3 as Table III and Fig. 2d
  as Fig. 2(d); "Fig" and "Figs" are read with or without the period. The
  supplement keeps its S-numbering and refers to the manuscript in IEEE
  numbering.
- Citations become numbered IEEE references, written out rather than as ranges
  ("[6], [7], [8]"). IEEEtran.bst ignores several fields, so the IEEE copy of
  the bibliography moves them. Software and dataset entries become misc
  entries. The version, the access date, the DOI (last, as in IEEE's forms)
  and, for an entry without a DOI, the arXiv identifier go into the note. A
  misc entry's publisher becomes its howpublished or organization unless it
  repeats the author.
- Some source fields are left out on purpose. A paper with a DOI is cited
  without its arXiv identifier, because IEEE cites the version of record; the
  arXiv primary class is not printed; and the maintainers' "Undated page" note
  gives way to the access date.
- IEEEtran.bst sets reference titles in sentence case, as IEEE asks. The copy
  protects what that would damage: acronyms, single capitals and words with
  inner capitals in titles ("3-D"), a note's leading acronym ("MIT") and its
  "Accessed" label. Proper nouns that no rule can recognise are braced in the
  source bibliography. Accented letters are written as LaTeX accents.
- A control entry at the top of references.bib makes IEEEtran.bst list the
  first author and "et al." when a reference has more than six authors, as
  IEEE asks.
- Wide tables span both columns and small ones sit in one. The manuscript's
  tables and figures go at the top of a page or, when the floats waiting fill
  most of a page, on a page of their own, so no text page is left holding
  floats alone. The supplement's tables break across pages; each caption stays
  on its table's first page and a continuation page repeats the head under
  "Table Sn (continued)".
- The columns of a table that wrap their text share its width in proportion
  to that text, measured as the printed width of their cells in the documents'
  fonts, rather than equally; none is narrower than half an equal share or
  than its longest word. Each takes a tabularx `\hsize` factor. A table's
  factors sum to its number of wrapping columns, as tabularx requires, less a
  few hundred-thousandths where TeX's rounding would otherwise leave the table
  short of its width. A table keeps equal widths unless unequal ones are
  estimated to shorten it.
- A figure is included as the vector PDF beside its PNG (figure_3.pdf beside
  figure_3.png) when there is one, and as the PNG otherwise. Its printed width,
  the full text width or 0.85 or 0.72 of it, still follows the PNG's aspect
  ratio, so the two files of a figure must be kept in step.
- The supplement's figures, written as an image `![Figure S1.](...)` followed
  by a `**Figure S1.**` caption paragraph, are labelled "Figure S1." in the
  text like its tables instead of being numbered by LaTeX. They float, where
  they stand or at the top of a page, so the text of their section fills the
  page before them, and never leave their section: before each section the
  figures still waiting go to the top of the next page, and no figure goes
  above its section's heading. References to them ("Fig. S1", "Fig S1", "Figs.
  S1 and S2") stay as text in both documents and must name a figure that the
  supplement has.
- Display math (`$$ ... $$`) becomes a numbered equation in the manuscript, as
  IEEE numbers displayed equations, and stays unnumbered in the supplement. An
  equation joins the paragraph before it, and the text after it when that
  text continues the sentence in lower case ("where ..."). Display math in a
  caption, table cell, heading, the abstract or the back matter stops the
  build, as does a code block fenced as `math`, which GitHub shows as an
  equation. Inline math (`$...$`) is kept, and Unicode symbols in math (≤, ×,
  −) become math commands.
- A fenced code block is copied as it is, as verbatim: no citation,
  reference, link, math or Unicode in it is converted, and its language (as in
  a fence opened with `sh`) is dropped, since the LaTeX loads no highlighting
  macros. Code must be ASCII and fenced; an indented code block or a fence
  that is never closed stops the build. Keep code lines short: a line of code
  longer than 42 characters overflows a column of the manuscript.
- The supplement opens by naming the manuscript's title instead of linking the
  markdown draft.
- The AI-use statement moves into the Acknowledgment, as IEEE requires. The
  CRediT, competing-interest and funding sections stay as comments.

Search main.tex for TODO to find the author block, the funding sentence and the
biography and photograph. The AI-use statement already names the system, the
sections and the level of use; check it against the final text.

The converter stops with an error rather than guess when it meets markdown it
does not handle. Examples are a citation with a locator, a reference to a
section, table or figure that neither the manuscript nor the supplement has,
a table without a caption, and a manuscript title that no longer matches the
IEEE one in the script. The module docstring lists every case.

## Regenerate, upload and compile

Regenerating overwrites manual edits in this folder. Once editing moves to
Overleaf, treat the Overleaf project as the source. From the repository root
(`--help` prints the arguments):

```sh
python3 scripts/paper_to_ieee.py PANDOC=/path/to/pandoc \
  ZIP=work/paper-ieee/jstars-overleaf.zip
```

The zip holds the three sources and, in a figures folder, the figure files
that the two documents include. Upload it to Overleaf with New Project, Upload
Project. Both documents compile with pdfLaTeX and BibTeX, Overleaf's defaults,
and suppress pdfTeX's harmless warning about a page that holds several PDF
figures with page groups, as cairo writes them:

```sh
cd paper/ieee
pdflatex main && bibtex main && pdflatex main && pdflatex main
pdflatex supplement && bibtex supplement && pdflatex supplement && pdflatex supplement
```

From the repository root, the converter's tests run the end-to-end checks
when pandoc is on the path or named in the `PANDOC` environment variable. They
compare every word and table row of the markdown with the LaTeX, and the
numbers in both directions, leaving math aside and comparing code as it is. A
small synthetic paper in a temporary folder covers what the paper may not use
yet: PDF figures, supplementary figures, display math, code blocks and the
zip. A BibTeX check of the whole reference list runs when bibtex is on the
path or named in `BIBTEX`, with or without pandoc:

```sh
PANDOC=/path/to/pandoc BIBTEX=/path/to/bibtex \
  python3 -m unittest discover -s tests -p 'test_paper_to_ieee.py'
```
