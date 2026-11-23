# ISPRS Journal version

This folder holds the LaTeX version of the [draft paper](../manuscript.md) for
the ISPRS Journal of Photogrammetry and Remote Sensing, an Elsevier journal. It
is generated from the markdown by
[paper_to_elsevier.py](../../scripts/paper_to_elsevier.py) and is the starting
point for editing on Overleaf.

- [main.tex](main.tex): the manuscript in Elsevier's elsarticle class, preprint
  layout: 12 pt type on A4, single column, with line numbers for the
  reviewers.
- [supplement.tex](supplement.tex): the supplement, submitted as a separate
  PDF.
- [references.bib](references.bib): an Elsevier copy of the
  [bibliography](../../docs/references.bib).

The figures are read from [../figures](../figures/), so they are not copied
here: a figure's PDF where there is one beside its PNG, otherwise the PNG.

## What the conversion changes

The converter reuses the machinery of the
[IEEE version's converter](../ieee/README.md): its handling of tables, figures,
display math, code blocks and the references to sections, tables and figures.
What differs is the journal's form.

- Citations are author-year, through natbib and elsarticle-harv.bst. A
  bracketed citation prints as "(Kaartinen et al., 2012; Jakubowski et al.,
  2013)" and a narrative one as "Jakubowski et al. (2013)".
- Sections, tables and figures keep the markdown's numbers: Section 4.2,
  Table 3, Fig. 2d. The build stops if the section numbers are not the
  sequence LaTeX prints. The supplement refers to the manuscript by the same
  numbers.
- The front matter keeps the highlights, the abstract and the keywords. The
  build stops if there are not three to five highlights of at most 85
  characters, or more than six keywords, the journal's limits. elsarticle
  prints the highlights on a page before the title page.
- The back matter keeps the markdown's sections in order: CRediT statement,
  competing interest, funding, data and code availability, acknowledgements
  and the declaration of generative AI. The journal asks for the declaration
  immediately before the references, so the build stops if it is not last. A
  section that still reads "To be completed" carries a TODO comment.
- Tables take booktabs rules, with no vertical rules or shading, as the
  journal asks, and the caption above. A table whose words cannot fit the
  portrait width goes on a landscape page of its own (Tables 3, 5 and 6), in
  10 pt type where it fits and 8 pt otherwise. Floats are placed next to the
  text that cites them where they fit, as the journal asks for the first
  submission.
- The supplement's tables break across pages and repeat their head, and its
  figures are labelled "Figure S1." in the text, as in the IEEE version.
- A figure prints at the width it was drawn, as a share of the text width
  (160 mm in the manuscript, 170 mm in the supplement); the figures drawn for
  the IEEE page are wider and print at the full text width.
- In the copy of the bibliography, software and dataset entries become misc
  entries. Version, notes and access dates ("Accessed 2 October 2026") go into
  the note, and a paper with a DOI is cited without its arXiv identifier.
  elsarticle-harv.bst sets titles in sentence case, so acronyms, single
  capitals and words with inner capitals are braced, as in the IEEE copy, and
  a note keeps the case of its first letter. DOIs print as <https://doi.org/>
  links.

Search main.tex for TODO to find the author block and the sections still to be
completed.

## Before submission

The journal's requirements below were read in its guide for authors on 21
October 2026. Check them again at submission.

- Complete the author block in main.tex: every author, each affiliation with
  its full postal address and country, and the corresponding author's e-mail
  address. The ORCID iD is in.
- Complete the CRediT statement, the declaration of competing interest and the
  funding statement in the markdown. The journal also takes the competing
  interest on Elsevier's declaration template, uploaded in Editorial Manager
  even when there is none. Without funding, the guide's sentence is: "This
  research did not receive any specific grant from funding agencies in the
  public, commercial, or not-for-profit sectors."
- Choose the publishing route: subscription, at no charge to the author, or
  open access at an article publishing charge of USD 3,800, the list price on
  21 October 2026.
- The guide asks that abbreviations that are not standard in the field be
  defined in a footnote on the first page. This version has no such footnote;
  the text defines each abbreviation at its first use.
- The first submission is a single PDF in any layout: main.pdf, with
  supplement.pdf as supplementary material. The editable LaTeX and the
  highlights as a separate file are asked for at revision.
- Elsevier marks data references with "[dataset]". Here the dataset entries,
  the three NEON products among them, say "Dataset" in their note; add the tag
  if the copy editor asks for it.
- Replace "DOI to be assigned at deposit" once the archive is deposited, then
  regenerate this folder.

The journal sets no length limit for research papers, no word limit for the
abstract (246 words) and at most six keywords (six).

## Regenerate, upload and compile

Regenerating overwrites manual edits in this folder. Once editing moves to
Overleaf, treat the Overleaf project as the source. From the repository root
(`--help` prints the arguments):

```sh
python3 scripts/paper_to_elsevier.py PANDOC=/path/to/pandoc \
  ZIP=work/paper-elsevier/isprs-overleaf.zip
```

The zip holds the three sources and, in a figures folder, the figure files
that the two documents include. Upload it to Overleaf with New Project, Upload
Project. Both documents compile with pdfLaTeX and BibTeX, Overleaf's defaults;
elsarticle, elsarticle-harv.bst and the rotating package are part of TeX Live:

```sh
cd paper/elsevier
pdflatex main && bibtex main && pdflatex main && pdflatex main
pdflatex supplement && bibtex supplement && pdflatex supplement && pdflatex supplement
```

On 23 November 2026 the manuscript compiled to 36 pages and the supplement to
29, with no overfull lines and no BibTeX warnings.

From the repository root, the converter's tests run the end-to-end checks
when pandoc is on the path or named in the `PANDOC` environment variable. They
compare every word, number and table row of the markdown with the LaTeX and
check the journal's front and back matter rules, on the paper and on a small
synthetic paper. A BibTeX check of the whole reference list runs when bibtex
is on the path or named in `BIBTEX`:

```sh
PANDOC=/path/to/pandoc BIBTEX=/path/to/bibtex \
  python3 -m unittest discover -s tests -p 'test_paper_to_elsevier.py'
```
