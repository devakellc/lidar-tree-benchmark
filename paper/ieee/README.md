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
  them no longer mentions them. The keywords become IEEE Index Terms in
  alphabetical order, and headings take IEEE headline style ("Related Work")
  in both documents; the last section is "Conclusion", singular, as in IEEE
  journals.
- Sections are numbered I, II and so on, and subsections A, B and so on. Every
  reference to a manuscript section, table or figure is a `\ref`, so Section
  4.2 of the markdown prints as Section IV-B, Table 3 as Table III and Fig. 2d
  as Fig. 2(d). The supplement keeps its S-numbering and refers to the
  manuscript in IEEE numbering.
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
- Wide tables span both columns and small ones sit in one. The supplement's
  tables break across pages; each caption stays on its table's first page and
  a continuation page repeats the head under "Table Sn (continued)".
- The supplement opens by naming the manuscript's title instead of linking the
  markdown draft.
- The AI-use statement moves into the Acknowledgment, as IEEE requires. The
  CRediT, competing-interest and funding sections stay as comments.

Search main.tex for TODO to find the author block, the funding sentence, the
biography and photograph, and the detail IEEE asks for in the AI-use
statement.

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

The zip holds the three sources and a figures folder. Upload it to Overleaf
with New Project, Upload Project. Both documents compile with pdfLaTeX and
BibTeX, Overleaf's defaults:

```sh
cd paper/ieee
pdflatex main && bibtex main && pdflatex main && pdflatex main
pdflatex supplement && bibtex supplement && pdflatex supplement && pdflatex supplement
```

From the repository root, the converter's tests run the end-to-end checks
when pandoc is on the path or named in the `PANDOC` environment variable. They
compare every word and table row of the markdown with the LaTeX, and the
numbers in both directions. A BibTeX check of the whole reference list runs
when bibtex is on the path or named in `BIBTEX`, with or without pandoc:

```sh
PANDOC=/path/to/pandoc BIBTEX=/path/to/bibtex \
  python3 -m unittest discover -s tests -p 'test_paper_to_ieee.py'
```
