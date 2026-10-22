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
here.

## What the conversion changes

- The highlights are dropped, and a sentence of Section 6.8 that referred to
  them no longer mentions them. The keywords become IEEE Index Terms in alphabetical
  order, and headings take IEEE headline style ("Related Work") in both
  documents.
- Sections are numbered I, II and so on, and subsections A, B and so on. Every
  reference to a manuscript section, table or figure is a `\ref`, so Section
  4.2 of the markdown prints as Section IV-B and Table 3 as Table III. The
  supplement keeps its S-numbering and refers to the manuscript in IEEE
  numbering.
- Citations become numbered IEEE references. The IEEE copy of the bibliography
  is written so that IEEEtran.bst prints every field of the source. Software
  and dataset entries become misc entries. The version, the access date, the
  DOI and the arXiv identifier move into the note or howpublished field, and
  a misc entry's publisher becomes its howpublished or organization.
- IEEEtran.bst sets reference titles in sentence case, as IEEE asks. The copy
  protects what that would damage: acronyms, single capitals and words with
  inner capitals in titles ("3-D"), and a note's leading acronym ("MIT").
  Proper nouns that no rule can recognise are braced in the source
  bibliography. Accented letters are written as LaTeX accents.
- Wide tables span both columns and small ones sit in one; the supplement's
  tables break across pages, with each caption kept on its table's first page.
- The supplement opens by naming the manuscript's title instead of linking the
  markdown draft.
- The AI-use statement moves into the Acknowledgment, as IEEE requires. The
  CRediT, competing-interest and funding sections stay as comments.

Search main.tex for TODO to find the author block, the funding sentence and
the detail IEEE asks for in the AI-use statement.

The converter stops with an error rather than guess when it meets markdown it
does not handle, such as a citation with a locator, a reference to a section,
table or figure that does not exist, or a manuscript title that no longer
matches the IEEE one in the script.

## Regenerate, upload and compile

Regenerating overwrites manual edits in this folder. Once editing moves to
Overleaf, treat the Overleaf project as the source. From the repository root
(`--help` prints the arguments):

```sh
python3 scripts/paper_to_ieee.py PANDOC=/path/to/pandoc \
  ZIP=work/paper-ieee/jstars-overleaf.zip
```

The zip holds the three sources and a figures folder. Upload it to Overleaf
with New Project, Upload Project. Both documents compile with pdfLaTeX and
BibTeX, Overleaf's defaults:

```sh
cd paper/ieee
pdflatex main && bibtex main && pdflatex main && pdflatex main
pdflatex supplement && bibtex supplement && pdflatex supplement && pdflatex supplement
```

From the repository root, the converter's tests run the end-to-end checks
when pandoc is on the path or named in the `PANDOC` environment variable, and
a BibTeX check of the reference list when bibtex is on the path or named in
`BIBTEX`. The checks compare every word, number and table row of the markdown
with the LaTeX:

```sh
PANDOC=/path/to/pandoc BIBTEX=/path/to/bibtex \
  python3 -m unittest discover -s tests -p 'test_paper_to_ieee.py'
```
