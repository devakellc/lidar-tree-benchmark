"""Regressions for scripts/paper_to_ieee.py (markdown to IEEE LaTeX).

The unit tests need no external tools. The end-to-end test runs the converter
on the repository's paper when pandoc is available (on PATH or via the PANDOC
environment variable) and checks the generated LaTeX for the defects that would
stop a pdfLaTeX + BibTeX build or silently drop content.

    python3 -m unittest discover -s tests -p 'test_paper_to_ieee.py'
"""
import importlib.util
import os
import re
import shutil
import tempfile
import unittest
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("paper_to_ieee", ROOT / "scripts/paper_to_ieee.py")
p2i = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p2i)
NB = "\u00a0"

BIB = r"""% header
@article{kuhn1955hungarian,
  author  = {Kuhn, Harold W.},
  title   = {The {Hungarian} method},
  journal = {Naval Research Logistics Quarterly},
  year    = {1955},
  doi     = {10.1002/nav.3800020109},
}

@misc{zhan2026forestquery,
  author        = {Zhan, Zhihao and Tao, Le and Tian, Yifei},
  title         = {{ForestQuery}: query learning},
  year          = {2026},
  eprint        = {2610.03403},
  archiveprefix = {arXiv},
}

@software{roussel2026lasr,
  author       = {Roussel, Jean-Romain},
  title        = {{lasR}},
  year         = {2026},
  url          = {https://github.com/r-lidar/lasR},
}

@article{wenger2012assessing,
  author  = {Wenger, Seth J. and Olden, Julian D.},
  title   = {Assessing transferability},
  journal = {Methods in Ecology and Evolution},
  year    = {2012},
  doi     = {10.1111/j.2041-210X.2011.00170.x},
  note    = {Original note},
}

@article{pleso2020,
  author  = {Ple{\c{s}}oianu, Alin-Ionu{\c{t}} and Dr{\u{a}}gu{\c{t}}, Lucian},
  title   = {Hyypp\"a and Ple\c{s}oianu in UTF-8: Hyyppä, Pleşoianu, Drăguț},
  journal = {Remote Sensing},
  year    = {2020},
}
"""


class NumberingTests(unittest.TestCase):
    def test_ieee_section_numbers(self):
        self.assertEqual(p2i.roman(4), "IV")
        self.assertEqual(p2i.roman(9), "IX")
        self.assertEqual(p2i.ieee_section_number("4"), "IV")
        self.assertEqual(p2i.ieee_section_number("2.1"), "II-A")
        self.assertEqual(p2i.ieee_section_number("4.10"), "IV-J")


class CitationTests(unittest.TestCase):
    def setUp(self):
        self.authors = p2i.bib_authors(BIB)

    def test_author_names_for_narrative_citations(self):
        self.assertEqual(self.authors["kuhn1955hungarian"], "Kuhn")
        self.assertEqual(self.authors["wenger2012assessing"], "Wenger and Olden")
        self.assertEqual(self.authors["zhan2026forestquery"], "Zhan et al.")

    def test_bracketed_group_becomes_one_cite_with_tie(self):
        out = p2i.convert_citations("as shown [@kuhn1955hungarian; @wenger2012assessing].", self.authors)
        self.assertEqual(out, f"as shown{NB}\\cite{{kuhn1955hungarian,wenger2012assessing}}.")

    def test_narrative_citation_gets_author_name(self):
        out = p2i.convert_citations("the method of @kuhn1955hungarian is", self.authors)
        self.assertEqual(out, f"the method of Kuhn{NB}\\cite{{kuhn1955hungarian}} is")

    def test_unknown_narrative_key_stops(self):
        with self.assertRaises(SystemExit):
            p2i.convert_citations("see @nosuchkey2020", self.authors)


class ReferenceTests(unittest.TestCase):
    def test_main_mode_uses_labels_and_keeps_supplement_items(self):
        out = p2i.convert_refs("Sections 4.5 and 5.2, Section S12, Tables 3, 5 and S12c, Fig. 2d", "main")
        self.assertIn(f"Sections{NB}\\ref{{sec:4.5}} and \\ref{{sec:5.2}}", out)
        self.assertIn(f"Section{NB}S12", out)
        self.assertIn(f"Tables{NB}\\ref{{tab:3}}, \\ref{{tab:5}} and S12c", out)
        self.assertIn(f"Fig.{NB}\\ref{{fig:2}}d", out)

    def test_ranges_and_dash_lists(self):
        out = p2i.convert_refs("Sections 2.1 to 2.5", "main")
        self.assertEqual(out, f"Sections{NB}\\ref{{sec:2.1}} to \\ref{{sec:2.5}}")

    def test_supplement_mode_writes_ieee_numbers(self):
        out = p2i.convert_refs("Table 4 of the manuscript and Section 4.10 of it, Table S15", "supp")
        self.assertIn(f"Table{NB}IV of the manuscript", out)
        self.assertIn(f"Section{NB}IV-J of it", out)
        self.assertIn(f"Table{NB}S15", out)


class LatexTextTests(unittest.TestCase):
    def test_unicode_mapping(self):
        out = p2i.unicode_to_latex("−0.05 at 2 pulses/m² — 3 × 3, τ ≤ 1, a–b, Hyyppä")
        self.assertEqual(out, '$-$0.05 at 2 pulses/m\\textsuperscript{2} --- 3 $\\times$ 3, $\\tau$ $\\leq$ 1, '
                              'a--b, Hyypp{\\"a}')

    def test_latex_accents_and_unknown_character(self):
        self.assertEqual(p2i.latex_accents("Pleşoianu Drăguț Křen"), r"Ple{\c{s}}oianu Dr{\u{a}}gu{\c{t}} K{\v{r}}en")
        with self.assertRaises(SystemExit):
            p2i.latex_accents("\u4e2d")

    def test_bracket_unescape_keeps_risky_positions(self):
        tex = "F1 0.4 {[}0.3, 0.5{]}\n\\item {[}a{]}\n& {[}b{]} \\\\\n{[}c{]}"
        out = p2i.unescape_brackets(tex)
        self.assertIn("F1 0.4 [0.3, 0.5]", out)
        self.assertIn("\\item {[}a]", out)
        self.assertIn("& {[}b]", out)


class BibliographyTests(unittest.TestCase):
    def test_ieee_bib(self):
        out = p2i.ieee_bib(BIB)
        # BibTeX reads any at-sign as an entry start, even in a % comment.
        self.assertNotIn("@", out.split("\n@", 1)[0])
        self.assertTrue(all(ord(ch) < 128 for ch in out))
        self.assertIn("@misc{roussel2026lasr,", out)
        self.assertNotIn("@software", out)
        self.assertRegex(out, r"(?s)@misc\{zhan2026forestquery,.*howpublished = \{arXiv:2610\.03403\}")
        self.assertIn(r"note = {doi: \url{10.1002/nav.3800020109}}", out)
        self.assertIn(r"note = {doi: \url{10.1111/j.2041-210X.2011.00170.x}. Original note}", out)
        self.assertEqual(out.count("note = {"), 2)  # one note per entry with a DOI

    def test_pipe_table_alignment(self):
        header, aligns, body = p2i.parse_pipe_table("| A | B | C |\n| --- | ---: | :---: |\n| x | 1 | y |\n")
        self.assertEqual(header, ["A", "B", "C"])
        self.assertEqual(aligns, ["l", "r", "c"])
        self.assertEqual(body, [["x", "1", "y"]])


def find_pandoc():
    cand = os.environ.get("PANDOC") or shutil.which("pandoc")
    return cand if cand and (Path(cand).is_file() or shutil.which(cand)) else None


@unittest.skipUnless(find_pandoc(), "pandoc not available (set PANDOC=/path/to/pandoc)")
class EndToEndTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        out = Path(cls.tmp.name) / "ieee"
        p2i.main([f"OUT={out}", f"PANDOC={find_pandoc()}"])
        cls.main_tex = (out / "main.tex").read_text(encoding="utf-8")
        cls.supp_tex = (out / "supplement.tex").read_text(encoding="utf-8")
        cls.bib = (out / "references.bib").read_text(encoding="utf-8")

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_outputs_are_ascii(self):
        for text in (self.main_tex, self.supp_tex, self.bib):
            self.assertEqual([c for c in set(text) if ord(c) > 127], [])

    def test_every_cite_key_is_in_the_bibliography(self):
        keys = set(re.findall(r"^@\w+\{([a-z0-9]+),", self.bib, flags=re.M))
        for tex in (self.main_tex, self.supp_tex):
            cited = {k.strip() for group in re.findall(r"\\cite\{([^}]*)\}", tex) for k in group.split(",")}
            self.assertEqual(cited - keys, set())

    def test_every_ref_has_a_label(self):
        labels = set(re.findall(r"\\label\{([^}]*)\}", self.main_tex))
        refs = set(re.findall(r"\\ref\{([^}]*)\}", self.main_tex))
        self.assertEqual(refs - labels, set())
        self.assertEqual(len(labels), len(re.findall(r"\\label\{", self.main_tex)))  # no duplicate labels

    def test_floats_highlights_and_index_terms(self):
        self.assertEqual(len(re.findall(r"\\begin\{figure\*\}", self.main_tex)), 7)
        self.assertEqual(len(re.findall(r"\\begin\{table\*?\}", self.main_tex)), 8)
        self.assertNotIn("Highlights", self.main_tex)
        self.assertIn("\\begin{IEEEkeywords}", self.main_tex)
        self.assertNotIn("longtable", self.main_tex)  # longtable fails in two-column mode

    def test_no_number_of_the_manuscript_is_lost(self):
        md = (ROOT / "paper/manuscript.md").read_text(encoding="utf-8")
        md = re.sub(r"## Highlights\n.*?(?=\n## )", "", md, flags=re.S)  # dropped on purpose
        md = re.sub(r"<!--.*?-->", "", md, flags=re.S)  # lint directives
        md = re.sub(r"\*\*(Figure|Table) \d+\.\*\*|!\[Figure \d+\.\]", "", md)  # caption labels become \label
        num = re.compile(r"\d+(?:[.,]\d+)*")
        missing = Counter(num.findall(md)) - Counter(num.findall(self.main_tex))
        self.assertEqual(dict(missing), {})


if __name__ == "__main__":
    unittest.main()
