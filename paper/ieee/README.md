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

- The highlights are dropped and the keywords become IEEE Index Terms in
  alphabetical order.
- Sections are numbered I, II and so on, and subsections A, B and so on. Every
  reference to a manuscript section, table or figure is a `\ref`, so Section
  4.2 of the markdown prints as Section IV-B and Table 3 as Table III. The
  supplement keeps its S-numbering and refers to the manuscript in IEEE
  numbering.
- Citations become numbered IEEE references. The IEEE copy of the bibliography
  turns software entries into misc entries, adds arXiv identifiers, moves DOIs
  into the note field, which IEEEtran.bst would otherwise drop, and writes
  accented letters as LaTeX accents.
- Wide tables span both columns and small ones sit in one; the supplement's
  tables break across pages.
- The AI-use statement moves into the Acknowledgment, as IEEE requires. The
  CRediT, competing-interest and funding sections stay as comments.

Search main.tex for TODO to find the author block, the funding sentence and
the detail IEEE asks for in the AI-use statement.

## Regenerate, upload and compile

Regenerating overwrites manual edits in this folder. Once editing moves to
Overleaf, treat the Overleaf project as the source.

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

The converter's tests run the end-to-end checks when pandoc is on the path or
named in `PANDOC`:

```sh
python3 -m unittest discover -s tests -p 'test_paper_to_ieee.py'
```
