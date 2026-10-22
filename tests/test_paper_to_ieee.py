"""Regressions for scripts/paper_to_ieee.py (markdown to IEEE LaTeX).

The unit tests need no external tools. The pandoc tests and the end-to-end
tests run when pandoc is available (on PATH or via the PANDOC environment
variable); the end-to-end tests convert the repository's paper and check the
LaTeX for defects that would stop a pdfLaTeX + BibTeX build or silently drop
content, and convert a small synthetic paper in a temporary copy of the
repository layout to exercise what the real paper may not use yet (PDF figures,
supplementary figures, display math, the Overleaf zip). The BibTeX test runs
IEEEtran.bst on the IEEE copy of the bibliography when bibtex is available (on
PATH or via BIBTEX), with or without pandoc. A PANDOC or BIBTEX variable that
does not name an executable is an error, not a reason to skip.

From the repository root:

    python3 -m unittest discover -s tests -p 'test_paper_to_ieee.py'
"""
import contextlib
import importlib.util
import io
import os
import re
import shutil
import struct
import subprocess
import tempfile
import unicodedata
import unittest
import zipfile
import zlib
from collections import Counter
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("paper_to_ieee", ROOT / "scripts/paper_to_ieee.py")
p2i = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p2i)
NB = "\u00a0"


def find_tool(env, name):
    cand = os.environ.get(env)
    if cand:
        if Path(cand).is_file() or shutil.which(cand):
            return cand
        raise RuntimeError(f"{env}={cand} does not name an executable {name}")
    return shutil.which(name)


PANDOC = find_tool("PANDOC", "pandoc")
BIBTEX = find_tool("BIBTEX", "bibtex")

BIB = r"""% header
% ---------------------------------------------------------------------------
% Benchmarks and datasets
% ---------------------------------------------------------------------------

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
  title        = {{lasR}: Fast and Pipeable Airborne {LiDAR} Data Tools},
  year         = {2026},
  version      = {0.21.0},
  url          = {https://github.com/r-lidar/lasR},
  urldate      = {2026-10-02},
  note         = {R package; the benchmark requires the {pre-devel}
                  build},
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

@article{beethoven1800,
  author  = {Ludwig van Beethoven and Jean de la Fontaine},
  title   = {International Benchmarking for Modeling 3-D Canopy Structure: A Test},
  journal = {Forests},
  year    = {1800},
}

@article{garcia2020,
  author  = {Garc{\'\i}a, Ana and Mart{\'{\i}}nez, Luis},
  title   = {Dotless i},
  journal = {Forests},
  year    = {2020},
  pages   = {},
}

@article{astrom2021,
  author  = {{\AA}str{\"o}m, Karl},
  title   = {Ring above},
  journal = {Forests},
  year    = 2021,
}

@article{hamraz2016,
  author  = {Hamraz, Hamid},
  title   = {Published with a preprint},
  journal = {Forests},
  year    = {2016},
  doi     = {10.1016/j.jag.2016.07.006},
  eprint  = {1701.00198},
}

@dataset{neon2026vst,
  author    = {{National Ecological Observatory Network (NEON)}},
  title     = {Vegetation structure ({DP1.10098.001})},
  publisher = {National Ecological Observatory Network (NEON)},
  year      = {2026},
  version   = {RELEASE-2026},
  doi       = {10.48443/pypa-qf12},
}

@misc{puliti2023data,
  author    = {Puliti, Stefano},
  title     = {{FOR-instance} data},
  publisher = {Zenodo},
  year      = {2023},
  version   = {1},
  doi       = {10.5281/zenodo.8287792},
  note      = {Dataset},
}

@software{roussel2026lidr,
  author       = {Roussel, Jean-Romain},
  title        = {{lidR}},
  howpublished = {CRAN},
  publisher    = {The R Foundation},
  year         = {2026},
  version      = {4.3.2},
  note         = {R package; version 4.3.2 is the installed release},
}

@software{full2026,
  author       = {Doe, Jane},
  title        = {Full},
  howpublished = {GitHub},
  organization = {Example Lab},
  publisher    = {Example Press},
  year         = {2026},
  version      = {0.21.0},
  note         = {Built from version 0.21.0.},
}

@inproceedings{agarwal2021deep,
  author    = {Agarwal, Rishabh and others},
  title     = {Deep reinforcement learning at the edge of the statistical precipice},
  booktitle = {Advances in Neural Information Processing Systems},
  year      = {2021},
  eprint    = {2108.13264},
}

@misc{weecology2024deepforesttree,
  author       = {{Weecology}},
  title        = {deepforest-tree},
  howpublished = {Hugging Face model repository},
  year         = {2024},
  urldate      = {2026-10-02},
  note         = {MIT licence; revision cc21436},
}

@misc{usgs2026topographic,
  author       = {{U.S. Geological Survey}},
  title        = "Topographic Data Quality Levels ({QLs}) of {"3DEP"}",
  howpublished = {3D Elevation Program web page},
  year         = {2026},
  urldate      = {2026-10-02},
  note         = {Undated page; year is the access year},
}

@misc{weights2025,
  author       = {Doe, Jane},
  title        = {Weights},
  howpublished = {GitHub},
  year         = {2025},
  eprint       = {2501.00001},
  version      = {1},
  note         = {Trained on 10 sites},
}

@misc{nrcan2025treeaibox,
  author       = {{Natural Resources Canada}},
  title        = {{TreeAIBox}},
  howpublished = {GitHub},
  year         = {2025},
  version      = {commit 5380ddec2799f55adb43b63407dd12ccf7abefae},
  note         = {Pinned commit dated 2025-09-27.},
  urldate      = {2026-10-02},
}
"""


def flat(text):
    return " ".join(text.split())


def write_png(path, width, height):
    """A valid greyscale PNG of width x height white pixels."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = b"".join(b"\x00" + b"\xff" * width for _ in range(height))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def write_pdf(path, width, height):
    """A valid one-page PDF of width x height points."""
    objs = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Resources << >> >>" % (width, height)]
    out, offsets = b"%PDF-1.4\n", []
    for i, obj in enumerate(objs, 1):
        offsets.append(len(out))
        out += b"%d 0 obj\n%s\nendobj\n" % (i, obj)
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
    out += b"".join(b"%010d 00000 n \n" % off for off in offsets)
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(out)


def entry(bib, key):
    m = re.search(r"(?s)@\w+\{" + key + r",.*?\n\}", bib)
    return flat(m.group(0)) if m else ""


class NumberingTests(unittest.TestCase):
    def test_ieee_section_numbers(self):
        self.assertEqual(p2i.roman(4), "IV")
        self.assertEqual(p2i.roman(9), "IX")
        self.assertEqual(p2i.ieee_section_number("4"), "IV")
        self.assertEqual(p2i.ieee_section_number("2.1"), "II-A")
        self.assertEqual(p2i.ieee_section_number("4.10"), "IV-J")

    def test_headline_style(self):
        cases = {
            "What separates the collapsing learned detector from the two that do not":
                "What Separates the Collapsing Learned Detector From the Two That Do Not",
            "Sites and airborne LiDAR": "Sites and Airborne LiDAR",
            "Dense-domain control and thinning": "Dense-Domain Control and Thinning",
            "What it is for": "What It Is For",
            "S10. Arm not analysed": "S10. Arm Not Analysed",
            "Results: the density response": "Results: The Density Response",
            "Recall at 2 m and 10 pulses/m²": "Recall at 2 m and 10 pulses/m²",
            "the detect_lasr runs": "The detect_lasr Runs",
            "scoring of $x + y$ and $f_1$ by density": "Scoring of $x + y$ and $f_1$ by Density",
            "the $a$ test": "The $a$ Test",
        }
        for title, want in cases.items():
            with self.subTest(title=title):
                self.assertEqual(p2i.headline(title), want)


class CitationTests(unittest.TestCase):
    def setUp(self):
        self.authors = p2i.bib_authors(BIB)

    def test_author_names_for_narrative_citations(self):
        self.assertEqual(self.authors["kuhn1955hungarian"], "Kuhn")
        self.assertEqual(self.authors["wenger2012assessing"], "Wenger and Olden")
        self.assertEqual(self.authors["zhan2026forestquery"], "Zhan et al.")
        self.assertEqual(self.authors["agarwal2021deep"], "Agarwal et al.")

    def test_names_are_decoded_and_keep_particles(self):
        self.assertEqual(self.authors["pleso2020"], "Ple\u015foianu and Dr\u0103gu\u0163")
        self.assertEqual(self.authors["beethoven1800"], "van Beethoven and de la Fontaine")
        self.assertEqual(self.authors["neon2026vst"], "National Ecological Observatory Network (NEON)")
        self.assertEqual(self.authors["garcia2020"], "Garc\u00eda and Mart\u00ednez")
        self.assertEqual(self.authors["astrom2021"], "\u00c5str\u00f6m")
        out = p2i.unicode_to_latex(p2i.convert_citations("by @pleso2020", self.authors))
        self.assertEqual(out, r"by Ple{\c{s}}oianu and Dr{\u{a}}gu{\c{t}}~\cite{pleso2020}")

    def test_bracketed_group_becomes_one_cite_with_tie(self):
        out = p2i.convert_citations("as shown [@kuhn1955hungarian; @wenger2012assessing].", self.authors)
        self.assertEqual(out, f"as shown{NB}\\cite{{kuhn1955hungarian,wenger2012assessing}}.")

    def test_narrative_citation_gets_author_name(self):
        out = p2i.convert_citations("the method of @kuhn1955hungarian is", self.authors)
        self.assertEqual(out, f"the method of Kuhn{NB}\\cite{{kuhn1955hungarian}} is")

    def test_unknown_narrative_key_stops(self):
        with self.assertRaises(SystemExit):
            p2i.convert_citations("see @nosuchkey2020", self.authors)

    def test_unsupported_citation_forms_stop(self):
        for text in ("[see @kuhn1955hungarian]", "[@kuhn1955hungarian, p. 3]",
                     "[@kuhn1955hungarian, @wenger2012assessing]", "[-@kuhn1955hungarian]",
                     "@kuhn1955hungarian [p. 3] shows"):
            with self.subTest(text=text), self.assertRaises(SystemExit):
                p2i.convert_citations(text, self.authors)


KNOWN = {"sec": {"1", "2", "2.1", "2.5", "4", "4.2", "4.3", "4.5", "4.10", "5.2"},
         "tab": {"2", "3", "4", "5"}, "fig": {"2", "3"},
         "ssec": {"S12", "S15"}, "stab": {"S12c", "S15", "S16a", "S16b"}}
KNOWN_S = dict(KNOWN, sfig={"S1", "S2"})  # a supplement with two figures


class ReferenceTests(unittest.TestCase):
    def test_main_mode_uses_labels_and_keeps_supplement_items(self):
        out = p2i.convert_refs("Sections 4.5 and 5.2, Section S12, Tables 3, 5 and S12c, Fig. 2d", "main", KNOWN)
        self.assertIn(f"Sections{NB}\\ref{{sec:4.5}} and \\ref{{sec:5.2}}", out)
        self.assertIn(f"Section{NB}S12", out)
        self.assertIn(f"Tables{NB}\\ref{{tab:3}}, \\ref{{tab:5}} and S12c", out)
        self.assertIn(f"Fig.{NB}\\ref{{fig:2}}(d)", out)

    def test_ranges_and_lists(self):
        cases = {
            "Sections 2.1 to 2.5": f"Sections{NB}\\ref{{sec:2.1}} to \\ref{{sec:2.5}}",
            "Sections 2.1\u20132.5": f"Sections{NB}\\ref{{sec:2.1}}\u2013\\ref{{sec:2.5}}",
            "Tables 2\u20134": f"Tables{NB}\\ref{{tab:2}}\u2013\\ref{{tab:4}}",
            "Tables 2, 3, and 4": f"Tables{NB}\\ref{{tab:2}}, \\ref{{tab:3}}, and \\ref{{tab:4}}",
            "Table 3 or 4": f"Table{NB}\\ref{{tab:3}} or \\ref{{tab:4}}",
            "Figures 2 and 3": f"Figures{NB}\\ref{{fig:2}} and \\ref{{fig:3}}",
        }
        for text, want in cases.items():
            with self.subTest(text=text):
                self.assertEqual(p2i.convert_refs(text, "main", KNOWN), want)

    def test_numbers_after_a_reference_stay_prose(self):
        cases = {
            "Section 4.2 and 4 m windows": f"Section{NB}\\ref{{sec:4.2}} and 4 m windows",
            "Table 2 and 2.5 pulses": f"Table{NB}\\ref{{tab:2}} and 2.5 pulses",
            "Section 5.2 and 3 sites": f"Section{NB}\\ref{{sec:5.2}} and 3 sites",
            "(Table 4, 2 rungs)": f"(Table{NB}\\ref{{tab:4}}, 2 rungs)",
            "Table 2 and 3 m²": f"Table{NB}\\ref{{tab:2}} and 3 m²",
        }
        for text, want in cases.items():
            with self.subTest(text=text):
                self.assertEqual(p2i.convert_refs(text, "main", KNOWN), want)

    def test_unknown_or_lettered_items_stop(self):
        for text in ("Section 9.9", "Table 7", "Figure 8", "Table 3a", "Table S99", "Section S3", "Fig. S1"):
            with self.subTest(text=text), self.assertRaises(SystemExit):
                p2i.convert_refs(text, "main", KNOWN)

    def test_supplement_group_reference(self):
        self.assertEqual(p2i.convert_refs("Table S16", "main", KNOWN), f"Table{NB}S16")

    def test_supplement_mode_writes_ieee_numbers(self):
        out = p2i.convert_refs("Table 4 of the manuscript and Section 4.10 of it, Table S15, Fig. 2d", "supp", KNOWN)
        self.assertIn(f"Table{NB}IV of the manuscript", out)
        self.assertIn(f"Section{NB}IV-J of it", out)
        self.assertIn(f"Table{NB}S15", out)
        self.assertIn(f"Fig.{NB}2(d)", out)

    def test_supplementary_figures_stay_text_in_both_documents(self):
        cases = {
            "Fig. S1": f"Fig.{NB}S1",
            "Figure S2 shows": f"Figure{NB}S2 shows",
            "Figs. S1 and S2": f"Figs.{NB}S1 and S2",
            "Figures S1–S2": f"Figures{NB}S1–S2",
            "Fig. S1b": f"Fig.{NB}S1(b)",
            "Fig. S2 or S1": f"Fig.{NB}S2 or S1",
            "Fig. S1 and 2 m windows": f"Fig.{NB}S1 and 2 m windows",
        }
        for mode in ("main", "supp"):
            for text, want in cases.items():
                with self.subTest(text=text, mode=mode):
                    self.assertEqual(p2i.convert_refs(text, mode, KNOWN_S), want)
        self.assertEqual(p2i.convert_refs("Figs. 2 and S1", "main", KNOWN_S), f"Figs.{NB}\\ref{{fig:2}} and S1")
        self.assertEqual(p2i.convert_refs("Figs. 2 and S1", "supp", KNOWN_S), f"Figs.{NB}2 and S1")

    def test_unknown_supplementary_figure_stops(self):
        for text in ("Fig. S3", "Figs. S1 and S3", "Figure S3b", "Figs. 2 and S9"):
            for mode in ("main", "supp"):
                with self.subTest(text=text, mode=mode), self.assertRaises(SystemExit):
                    p2i.convert_refs(text, mode, KNOWN_S)

    def test_numbers_include_supplementary_figures(self):
        md = "## 1. Intro\n\n**Figure 1.** A.\n"
        supp = ("## S1. One\n\n**Figure S1.** A.\n\n**Figure S2.** B.\n\n**Table S1.** C.\n\n"
                "Not a caption: **Figure S9.**\n")
        known = p2i.manuscript_numbers(md, supp)
        self.assertEqual(known["fig"], {"1"})
        self.assertEqual(known["sfig"], {"S1", "S2"})
        self.assertEqual(known["stab"], {"S1"})


class LatexTextTests(unittest.TestCase):
    def test_unicode_mapping(self):
        out = p2i.unicode_to_latex("−0.05 at 2 pulses/m² — 3 × 3, τ ≤ 1, a–b, Hyyppä")
        self.assertEqual(out, '$-$0.05 at 2 pulses/m\\textsuperscript{2} --- 3 $\\times$ 3, $\\tau$ $\\leq$ 1, '
                              'a--b, Hyypp{\\"a}')

    def test_latex_accents_and_unknown_character(self):
        # s with cedilla (U+015F), t with comma below (U+021B), r with caron
        self.assertEqual(p2i.latex_accents("Ple\u015foianu Dr\u0103gu\u021b K\u0159en"),
                         r"Ple{\c{s}}oianu Dr{\u{a}}gu{\textcommabelow{t}} K{\v{r}}en")
        with self.assertRaises(SystemExit):
            p2i.latex_accents("\u4e2d")

    def test_bracket_unescape_keeps_risky_positions(self):
        tex = "F1 0.4 {[}0.3, 0.5{]}\n\\item {[}a{]}\n& {[}b{]} \\\\\n{[}c{]}"
        out = p2i.unescape_brackets(tex)
        self.assertIn("F1 0.4 [0.3, 0.5]", out)
        self.assertIn("\\item {[}a]", out)
        self.assertIn("& {[}b]", out)

    def test_links(self):
        cases = {
            ("see [the code](https://example.org/x) now", "main"): "see the code (<https://example.org/x>) now",
            ("see [the code](https://example.org/x) now", "supp"): "see [the code](https://example.org/x) now",
            ("in [the study](../results/a.md)", "supp"): f"in [the study]({p2i.REPO_URL}results/a.md)",
            ("in [the study](../results/a.md)", "main"): "in the study",
            ("[t](<https://x.org/a>)", "main"): "t (<https://x.org/a>)",
            ('[t](https://x.org/a "A title")', "main"): "t (<https://x.org/a>)",
            ("![Figure 1.](figures/figure_1.png)", "main"): "![Figure 1.](figures/figure_1.png)",
            ("![Figure 1.](../figures/figure_1.png)", "supp"): "![Figure 1.](../figures/figure_1.png)",
        }
        for (text, mode), want in cases.items():
            with self.subTest(text=text, mode=mode):
                self.assertEqual(p2i.links(text, mode), want)

    def test_uncaptioned_table_and_stray_image_stop(self):
        with self.assertRaises(SystemExit):
            p2i.body_to_tex("Text.\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n", "main", {}, KNOWN)
        with self.assertRaises(SystemExit):
            p2i.snippet("An ![image](x.png) in the abstract.", "main", {}, KNOWN)


class FigureTests(unittest.TestCase):
    """Figures read from a temporary paper/figures folder."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        patcher = mock.patch.object(p2i, "REPO", self.root)
        patcher.start()
        self.addCleanup(patcher.stop)
        figs = self.root / "paper/figures"
        write_png(figs / "figure_1.png", 50, 20)      # aspect 2.5: full text width
        write_png(figs / "figure_2.png", 40, 40)      # aspect 1.0: 0.72 of it
        write_pdf(figs / "figure_2.pdf", 720, 144)    # the width follows the PNG, not the PDF
        write_png(figs / "figure_s1.png", 28, 20)     # aspect 1.4: 0.85 of it
        write_pdf(figs / "figure_s1.pdf", 280, 200)
        write_png(figs / "figure_s2.png", 20, 40)
        (figs / "fake.png").write_text("not a PNG")

    def test_png_figure_without_pdf(self):
        out = p2i.figure_tex("1", "figures/figure_1.png", "Cap.")
        self.assertEqual(out, "\\begin{figure*}[!t]\n\\centering\n"
                              "\\includegraphics[width=\\textwidth]{figures/figure_1.png}\n"
                              "\\caption{Cap.}\n\\label{fig:1}\n\\end{figure*}")

    def test_pdf_beside_the_png_is_included(self):
        out = p2i.figure_tex("2", "figures/figure_2.png", "Cap.")
        self.assertIn("\\includegraphics[width=0.72\\textwidth]{figures/figure_2.pdf}", out)
        self.assertNotIn("figure_2.png", out)
        self.assertEqual((p2i.FIG_WIDTH["2"], p2i.FIG_FILE["2"]), ("0.72\\textwidth", "figures/figure_2.pdf"))

    def test_supplementary_figure_is_labelled_in_the_text(self):
        out = p2i.figure_tex("S1", "figures/figure_s1.png", "Cap. with \\url{x}.", "supp")
        self.assertEqual(out, "\\begin{figure}[H]\n"
                              "{\\centering\\includegraphics[width=0.85\\textwidth]{figures/figure_s1.pdf}\\par}\n"
                              "\\medskip\n\\textbf{Figure S1.} Cap. with \\url{x}.\n\\end{figure}")
        out = p2i.figure_tex("S2", "figures/figure_s2.png", "Cap.", "supp")
        self.assertIn("{\\centering\\includegraphics[width=0.72\\textwidth]{figures/figure_s2.png}\\par}", out)
        self.assertNotRegex(out, r"\\caption|\\label")  # no automatic numbering

    def test_bad_figure_files_stop(self):
        (self.root / "figure_1.png").write_bytes((self.root / "paper/figures/figure_1.png").read_bytes())
        for path in ("../figure_1.png", str(self.root / "paper/figures/figure_1.png"), "figures/figure_1.pdf",
                     "figures/figure 1.png", "figures/missing.png", "figures/fake.png"):
            with self.subTest(path=path), self.assertRaises(SystemExit):
                p2i.figure_tex("1", path, "Cap.")

    def test_figures_must_be_numbered_for_their_document(self):
        # The numbering is checked before pandoc runs, so these need no pandoc.
        for md, mode in (("![Figure S1.](figures/figure_s1.png)\n\n**Figure S1.** Cap.\n", "main"),
                         ("![Figure 1.](figures/figure_1.png)\n\n**Figure 1.** Cap.\n", "supp"),
                         ("Text.\n\n**Figure S1.** A caption without its image.\n", "supp"),
                         ("![Figure S1.](figures/figure_s1.png)\n\nA paragraph instead of the caption.\n", "supp")):
            with self.subTest(md=md, mode=mode), self.assertRaises(SystemExit):
                p2i.body_to_tex(md, mode, {}, KNOWN_S)

    def test_graphics_files_skip_comments(self):
        tex = ("% \\includegraphics{photo}\n\\includegraphics[width=1in]{figures/a.pdf} "
               "\\includegraphics{figures/a.pdf}\n\\includegraphics{figures/b.png} % \\includegraphics{c}\n"
               "50\\% \\includegraphics{figures/d.png}")
        self.assertEqual(p2i.graphics_files(tex), ["figures/a.pdf", "figures/b.png", "figures/d.png"])

    def test_zip_carries_the_included_files(self):
        out = self.root / "out"
        out.mkdir()
        (out / "main.tex").write_text("\\includegraphics[width=\\textwidth]{figures/figure_2.pdf}\n"
                                      "\\includegraphics{figures/figure_1.png}\n% \\includegraphics{photo}\n")
        (out / "supplement.tex").write_text("{\\centering\\includegraphics[width=1in]{figures/figure_s1.pdf}\\par}\n")
        (out / "references.bib").write_text("% bib\n")
        z = p2i.write_zip(out, self.root / "up/jstars.zip")
        self.assertEqual(sorted(zipfile.ZipFile(z).namelist()),
                         ["figures/figure_1.png", "figures/figure_2.pdf", "figures/figure_s1.pdf",
                          "main.tex", "references.bib", "supplement.tex"])
        (out / "supplement.tex").write_text("\\includegraphics{figures/figure_9.pdf}\n")
        with self.assertRaises(SystemExit):
            p2i.write_zip(out, self.root / "up/other.zip")
        self.assertFalse((self.root / "up/other.zip").exists())


class MathTests(unittest.TestCase):
    def test_math_spans(self):
        tex = ("a \\(x\\) b \\[y\\] c \\\\[4pt] d \\begin{equation}z \\\\ w\\end{equation} "
               "e \\textbackslash{}( f \\(\\alpha \\\\\\) g")
        spans = [(tex[s:e], d) for s, e, d in p2i.math_spans(tex)]
        self.assertEqual(spans, [("\\(x\\)", False), ("\\[y\\]", True),
                                 ("\\begin{equation}z \\\\ w\\end{equation}", True), ("\\(\\alpha \\\\\\)", False)])
        self.assertEqual(p2i.math_spans("Row \\\\[4pt] and {[}0, 1{]} and \\$5"), [])
        with self.assertRaises(SystemExit):
            p2i.math_spans("a \\(x")

    def test_unicode_inside_math_becomes_math_commands(self):
        out = p2i.unicode_to_latex("a \u2212 b \\(x \u2212 y \u2264 z\u00b2 \u00d7 \u03c4\\) c \u2265 d")
        self.assertEqual(out, "a $-$ b \\(x - y \\leq{} z^{2} \\times{} \\tau{}\\) c $\\geq$ d")
        self.assertEqual(p2i.unicode_to_latex("\\[a\u00b7b\\]"), "\\[a\\cdot{}b\\]")
        with self.assertRaises(SystemExit):
            p2i.unicode_to_latex("\\(\u03c1\\)")  # rho: write \rho

    def test_display_math_is_numbered_and_joins_its_sentence(self):
        tex = ("Corrected F1 is\n\n\\[\nF = 1\n\\]\n\nwhere F is.\n\nNext.\n\n\\[ G \\]\n\nThe end. "
               "In text \\[H\\] here, \\(x\\) inline.")
        self.assertEqual(p2i.display_math(tex, numbered=True),
                         "Corrected F1 is\n\\begin{equation}\nF = 1\n\\end{equation}\nwhere F is.\n\nNext.\n"
                         "\\begin{equation}\nG\n\\end{equation}\n\nThe end. "
                         "In text \\begin{equation}\nH\n\\end{equation} here, \\(x\\) inline.")
        self.assertEqual(p2i.display_math(tex, numbered=False),
                         "Corrected F1 is\n\\[\nF = 1\n\\]\nwhere F is.\n\nNext.\n\\[\nG\n\\]\n\nThe end. "
                         "In text \\[\nH\n\\] here, \\(x\\) inline.")
        raw = "Raw:\n\n\\begin{equation}\nx\n\\end{equation}\n\nwhere"
        self.assertEqual(p2i.display_math(raw, numbered=True), raw)

    def test_math_fence_stops(self):
        for md in ("Text.\n\n```math\nx = 1\n```\n", "~~~ {.math}\nx\n~~~\n", "  ```  math\nx\n```\n"):
            with self.subTest(md=md), self.assertRaises(SystemExit):
                p2i.check_math_fence(md)
        for md in ("```python\nx\n```\n", "```mathematica\nx\n```\n", "Some math here.\n"):
            with self.subTest(md=md):
                p2i.check_math_fence(md)


class BibliographyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.out = p2i.ieee_bib(BIB)

    def test_no_at_sign_outside_entries_and_ascii(self):
        # BibTeX reads any at-sign as an entry start, even in a % comment.
        for line in self.out.splitlines():
            if not re.match(r"@\w+\{", line):
                self.assertNotIn("@", line)
        self.assertTrue(all(ord(ch) < 128 for ch in self.out))

    def test_section_headings_and_control_entry(self):
        self.assertIn("% Benchmarks and datasets", self.out)
        self.assertLess(self.out.index("% Benchmarks and datasets"), self.out.index("@article{kuhn1955hungarian"))
        self.assertLess(self.out.index("@IEEEtranBSTCTL{IEEEexample:BSTcontrol,"), self.out.index("@article{"))
        self.assertIn('CTLuse_forced_etal       = "yes"', self.out)
        self.assertIn('CTLdash_repeated_names   = "no"', self.out)

    def test_types_doi_and_eprint(self):
        self.assertIn("@misc{roussel2026lasr,", self.out)
        self.assertIn("@misc{neon2026vst,", self.out)
        self.assertNotIn("@software", self.out)
        self.assertNotIn("@dataset", self.out)
        self.assertIn("note = {arXiv:2610.03403}", entry(self.out, "zhan2026forestquery"))
        self.assertNotIn("howpublished", entry(self.out, "zhan2026forestquery"))
        self.assertIn(r"note = {doi: \url{10.1002/nav.3800020109}}", entry(self.out, "kuhn1955hungarian"))
        self.assertIn(r"note = {Original note, doi: \url{10.1111/j.2041-210X.2011.00170.x}}",
                      entry(self.out, "wenger2012assessing"))
        self.assertIn("note = {arXiv:2108.13264}", entry(self.out, "agarwal2021deep"))
        # IEEE cites the version of record: a paper with a DOI loses its arXiv identifier.
        self.assertIn(r"note = {doi: \url{10.1016/j.jag.2016.07.006}}", entry(self.out, "hamraz2016"))
        self.assertNotIn("1701.00198", self.out)
        for field in ("doi", "eprint", "archiveprefix", "version", "urldate", "publisher"):
            self.assertNotRegex(self.out, rf"(?m)^\s*{field}\s*=")

    def test_version_access_date_and_publisher_are_printed(self):
        # Only a note's first letter is case-changed, so 'R' after 'Version ...' needs no braces.
        self.assertIn("note = {Version 0.21.0. R package; the benchmark requires the {pre-devel} build. "
                      "Accessed: Oct. 2, 2026}", entry(self.out, "roussel2026lasr"))
        self.assertIn(r"note = {Version RELEASE-2026, doi: \url{10.48443/pypa-qf12}}", entry(self.out, "neon2026vst"))
        self.assertNotIn("howpublished", entry(self.out, "neon2026vst"))  # publisher repeats the author
        self.assertIn("howpublished = {Zenodo}", entry(self.out, "puliti2023data"))
        self.assertIn(r"note = {Version 1. Dataset, doi: \url{10.5281/zenodo.8287792}}", entry(self.out, "puliti2023data"))
        lidr = entry(self.out, "roussel2026lidr")
        self.assertIn("howpublished = {CRAN}", lidr)
        self.assertIn("organization = {The R Foundation}", lidr)
        self.assertIn("note = {{R} package; version 4.3.2 is the installed release}", lidr)  # version not repeated
        full = entry(self.out, "full2026")
        self.assertEqual(full.count("organization"), 1)
        self.assertIn("note = {Built from version 0.21.0. Example Press}", full)  # no doubled period
        self.assertIn("note = {Commit 5380ddec2799f55adb43b63407dd12ccf7abefae. Pinned commit dated 2025-09-27. "
                      "Accessed: Oct. 2, 2026}", entry(self.out, "nrcan2025treeaibox"))
        self.assertIn("note = {{A}ccessed: Oct. 2, 2026}", entry(self.out, "usgs2026topographic"))
        self.assertIn("note = {{MIT} licence; revision cc21436. Accessed: Oct. 2, 2026}",
                      entry(self.out, "weecology2024deepforesttree"))
        # A note that merely contains the digits of the version does not state it,
        # and a misc preprint's arXiv identifier opens the note even when howpublished is taken.
        self.assertIn("note = {arXiv:2501.00001. Version 1. Trained on 10 sites}", entry(self.out, "weights2025"))
        self.assertNotIn("pages", entry(self.out, "garcia2020"))  # an empty field is dropped
        with self.assertRaises(SystemExit):
            p2i.accessed("2026-10")

    def test_title_protection(self):
        self.assertIn("title = {International Benchmarking for Modeling 3-{D} Canopy Structure: A Test}",
                      entry(self.out, "beethoven1800"))
        self.assertIn('title = {Topographic Data Quality Levels ({QLs}) of {"3DEP"}}', entry(self.out, "usgs2026topographic"))
        cases = {
            "SAM 2: Segment Anything": "{SAM} 2: Segment Anything",
            "Data for the PointNet++ Benchmark": "Data for the {PointNet}++ Benchmark",
            "A New Method for Type II Errors": "A New Method for Type {II} Errors",
            "Equitability revisited: why the ``equitable threat score'' is not":
                "Equitability revisited: why the `equitable threat score' is not",
            r"Longleaf Pine (\emph{Pinus palustris} {Mill.}) Tree Attributes":
                r"Longleaf Pine (\emph{Pinus palustris} {Mill.}) Tree Attributes",
            "A {LiDAR}-CHM Comparison": "A {LiDAR}-{CHM} Comparison",
            "Fitting $\\alpha$-Shapes to ALS Data": "Fitting $\\alpha$-Shapes to {ALS} Data",
        }
        for title, want in cases.items():
            with self.subTest(title=title):
                self.assertEqual(p2i.protect_title(title), want)

    def test_note_protection(self):
        self.assertEqual(p2i.protect_note("R package"), "{R} package")
        self.assertEqual(p2i.protect_note("MIT licence"), "{MIT} licence")
        self.assertEqual(p2i.protect_note("Accessed: Oct. 2, 2026"), "{A}ccessed: Oct. 2, 2026")
        for note in ("Dataset", "Version 1", r"doi: \url{x}", "{MIT} licence"):
            self.assertEqual(p2i.protect_note(note), note)

    def test_parser_reads_nested_and_multiline_values(self):
        fields = dict(next(e for e in p2i.parse_bib(BIB) if e[1] == "roussel2026lasr")[2])
        self.assertEqual(fields["note"], "R package; the benchmark requires the {pre-devel} build")
        self.assertEqual(fields["title"], "{lasR}: Fast and Pipeable Airborne {LiDAR} Data Tools")
        fields = dict(next(e for e in p2i.parse_bib(BIB) if e[1] == "usgs2026topographic")[2])
        self.assertEqual(fields["title"], 'Topographic Data Quality Levels ({QLs}) of {"3DEP"}')
        self.assertEqual(dict(next(e for e in p2i.parse_bib(BIB) if e[1] == "astrom2021")[2])["year"], "2021")

    def test_parser_stops_on_unsupported_forms(self):
        for text in ('@string{jan = "January"}', '@preamble{"x"}', "@comment{x}", "@misc(k, title = {T})",
                     "@misc{k, title = {A} # {B}}", "@misc{k, month = jan}"):
            with self.subTest(text=text), self.assertRaises(SystemExit):
                p2i.parse_bib(text)

    def test_pipe_table_alignment(self):
        header, aligns, body = p2i.parse_pipe_table("| A | B | C |\n| --- | ---: | :---: |\n| x | 1 | y |\n")
        self.assertEqual(header, ["A", "B", "C"])
        self.assertEqual(aligns, ["l", "r", "c"])
        self.assertEqual(body, [["x", "1", "y"]])


class ArgumentTests(unittest.TestCase):
    def test_arguments_without_equals_stop_before_writing(self):
        for argv in (["--out", "x"], ["OUT"], ["NOPE=1"]):
            with self.subTest(argv=argv), self.assertRaises(SystemExit):
                p2i.main(argv)


@unittest.skipUnless(PANDOC, "pandoc not available (set PANDOC=/path/to/pandoc)")
class PandocTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        p2i.PANDOC = PANDOC

    def test_apostrophe_after_code_span(self):
        out = p2i.unicode_to_latex(p2i.pandoc("only `multichm`'s interval\n"))
        self.assertIn("\\texttt{multichm}'s", out)

    def test_snippets_stay_inline(self):
        snips = ["- 3", "+ 4", "* five", "1. first", "2) second", "> quoted", ": defined", "# hash", "| pipe",
                 "~ tilde", "= equals", "plain"]
        out = p2i.pandoc_snippets(snips)
        self.assertEqual(len(out), len(snips))
        for src, tex in zip(snips, out):
            with self.subTest(src=src):
                self.assertNotRegex(tex, r"\\begin\{|\\item|\\section|\\rule")
                self.assertIn(re.sub(r"^\W+|^\d+\W", "", src).strip(), tex)

    def test_inline_markup_at_the_start_is_kept(self):
        out = p2i.pandoc_snippets(["*Pinus* sp.", "**Total**", "--"])
        self.assertEqual(out[0], "\\emph{Pinus} sp.")
        self.assertEqual(out[1], "\\textbf{Total}")
        self.assertEqual(out[2], "--")

    def test_back_matter_may_hold_a_list(self):
        out = p2i.snippet("Data:\n\n- one\n- two\n", "main", {}, KNOWN)
        self.assertIn("\\begin{itemize}", out)

    def test_links_in_headings_captions_and_cells(self):
        md = ("## 1. Intro to [the code](https://example.org/a)\n\nText.\n\n"
              "**Table 2.** Caption with [a link](https://example.org/b).\n\n"
              "| A | B |\n| --- | --- |\n| [c](https://example.org/c) | 1 |\n")
        out = p2i.body_to_tex(md, "main", {}, KNOWN)
        self.assertNotIn("\\href", out)
        self.assertIn("\\protect\\url{https://example.org/a}", out)
        self.assertIn("\\caption{Caption with a link (\\protect\\url{https://example.org/b}).}", out)
        self.assertIn("c (\\url{https://example.org/c})", out)
        supp = p2i.body_to_tex(md.replace("1. Intro", "S1. Intro").replace("https://example.org/b", "../docs/b.md"),
                               "supp", {}, KNOWN)
        self.assertIn(f"\\href{{{p2i.REPO_URL}docs/b.md}}", supp)

    def test_display_math_becomes_a_numbered_equation(self):
        md = ("## 4. Methods\n\nCorrected F1 is\n\n$$\nF_c = \\frac{F - F_0}{1 - F_0}\n$$\n\n"
              "where $F_0 \u2264 F$ is the null F1 and $20 is not math.\n\nThe next paragraph.\n")
        out = p2i.body_to_tex(md, "main", {}, KNOWN)
        self.assertIn("Corrected F1 is\n\\begin{equation}\nF_c = \\frac{F - F_0}{1 - F_0}\n\\end{equation}\n"
                      "where \\(F_0 \\leq{} F\\) is the null F1 and \\$20 is not math.", out)
        self.assertNotIn("\\[", out)
        supp = p2i.body_to_tex(md.replace("4. Methods", "S1. Methods"), "supp", {}, KNOWN)
        self.assertIn("Corrected F1 is\n\\[\nF_c = \\frac{F - F_0}{1 - F_0}\n\\]\nwhere \\(F_0", supp)
        self.assertNotIn("equation", supp)

    def test_inline_math_in_captions_cells_and_back_matter(self):
        md = ("## 1. Intro\n\nText.\n\n**Table 2.** Scores of $F_1$ against $\\tau$.\n\n"
              "| A | $F_c$ |\n| --- | --- |\n| $x \u2212 1$ | 1 |\n")
        out = p2i.body_to_tex(md, "main", {}, KNOWN)
        self.assertIn("\\caption{Scores of \\(F_1\\) against \\(\\tau\\).}", out)
        self.assertIn("A & \\(F_c\\) \\\\", out)
        self.assertIn("\\(x - 1\\) & 1 \\\\", out)
        self.assertEqual(p2i.snippet("An abstract with $F_1 \u2265 0$.", "main", {}, KNOWN),
                         "An abstract with \\(F_1 \\geq{} 0\\).")

    def test_display_math_outside_the_body_text_stops(self):
        cases = [("snippet", "An abstract with $$x = 1$$ in it."),
                 ("body", "## 1. Intro\n\nText.\n\n**Table 2.** A $$x$$ caption.\n\n| A |\n| --- |\n| 1 |\n"),
                 ("body", "## 1. Intro\n\nText.\n\n**Table 2.** Caption.\n\n| A |\n| --- |\n| $$x$$ |\n"),
                 ("body", "## 1. The $$x$$ heading\n\nText.\n"),
                 ("body", "## 1. Intro\n\n```math\nx = 1\n```\n")]
        for kind, md in cases:
            with self.subTest(md=md), self.assertRaises(SystemExit):
                if kind == "snippet":
                    p2i.snippet(md, "main", {}, KNOWN)
                else:
                    p2i.body_to_tex(md, "main", {}, KNOWN)


ACCENT_CMD = re.compile(r"\{\\(?:[`'^\"~=.]|[cvukHr](?![A-Za-z])|textcommabelow)\s*\{?([A-Za-z])\}?\}")
LETTER_CMD = {"ae": "ae", "AE": "AE", "oe": "oe", "OE": "OE", "o": "o", "O": "O", "ss": "ss", "l": "l", "L": "L"}
TOKEN = re.compile(r"[a-z0-9]+(?:[.,][0-9]+)*")


def tokens(text):
    text = text.translate(str.maketrans({"æ": "ae", "ø": "o", "ß": "ss", "ł": "l", "œ": "oe"}))
    text = "".join(c for c in unicodedata.normalize("NFKD", text) if not unicodedata.combining(c))
    text = re.sub(r"(\d)\(([a-z])\)", r"\1\2", text)  # Fig. 2(d) and Fig. 2d are the same callout
    return Counter(TOKEN.findall(text.lower()))


def drop_command(tex, name, nargs):
    """Remove every \\name with its nargs brace-delimited arguments."""
    out, i = [], 0
    for m in re.finditer(r"\\" + name + r"(?![A-Za-z])", tex):
        if m.start() < i:
            continue
        out.append(tex[i:m.start()])
        j = m.end()
        for _ in range(nargs):
            while j < len(tex) and tex[j] in " \t\n%":
                j = tex.index("\n", j) + 1 if tex[j] == "%" else j + 1
            if tex[j] == "[":  # an optional argument
                j = tex.index("]", j) + 1
            depth = 0
            while True:
                depth += (tex[j] == "{") - (tex[j] == "}")
                j += 1
                if depth == 0:
                    break
        i = j
    out.append(tex[i:])
    return "".join(out)


def tex_words(tex):
    body = tex.split("\\begin{document}", 1)[1].split("\\end{document}", 1)[0]
    body = re.sub(r"(?<!\\)%.*", " ", body)
    # Math is not compared: equations, \[...\] and \(...\) (not the \\[4pt] of a row).
    body = re.sub(r"(?s)\\begin\{equation\}.*?\\end\{equation\}", " ", body)
    body = re.sub(r"(?s)(?<!\\)\\\[.*?\\\]|(?<!\\)\\\(.*?\\\)", " ", body)
    for name, nargs in (("title", 1), ("author", 1), ("markboth", 2), ("bstctlcite", 1), ("nocite", 1),
                        ("url", 1), ("includegraphics", 1)):
        body = drop_command(body, name, nargs)
    body = re.sub(r"\\href\{[^}]*\}", " ", body)  # the target; the link text stays
    body = re.sub(r"(?s)\\endfirsthead.*?\\endhead", " ", body)  # a supplement table's repeated head
    body = re.sub(r"\\multicolumn\{\d+\}", " ", body)
    body = re.sub(r"\\setlength\{\\tabcolsep\}\{[^}]*\}|\\renewcommand\{\\arraystretch\}\{[^}]*\}", " ", body)
    body = re.sub(r"\\\\\[\d+pt\]", " ", body)
    body = re.sub(r"\[[^\]]*\\(?:textwidth|columnwidth)\]", " ", body)
    # The supplement's caption labels, of its tables and of its figures.
    body = re.sub(r"\\textbf\{(?:Table|Figure) S?\d+[a-z]?\.\}", " ", body)
    body = re.sub(r"\\label\{(?:tab|fig):[^}]*\}", " ", body)  # LaTeX numbers floats itself
    body = body.replace("\\textsuperscript{2}", "\u00b2")
    body = ACCENT_CMD.sub(r"\1", body)
    body = re.sub(r"\{\\(ae|AE|oe|OE|o|O|ss|l|L)\}", lambda m: LETTER_CMD[m.group(1)], body)
    body = re.sub(r"\\IEEEPARstart\{(\w)\}\{(\w*)\}", r"\1\2", body)
    body = re.sub(r"\\(?:label|ref)\{sec:([^}]*)\}|\\ref\{(?:tab|fig):([^}]*)\}",
                  lambda m: m.group(1) or m.group(2), body)
    body = re.sub(r"\\cite\{[^}]*\}", " ", body)
    body = re.sub(r"\\[A-Za-z]+\*?", " ", body)
    body = re.sub(r"\\.", " ", body)
    return tokens(body)


# Read left to right as pandoc does: a code span that opens first keeps its
# dollar signs; $$...$$ is display math; inline math opens with a $ before a
# non-space and closes with a $ after a non-space and not before a digit, so
# $20,000 stays text.
MD_MATH = re.compile(r"(`[^`\n]*`)"
                     r"|(?<!\\)\$\$(?:(?!\n[ \t]*\n).)+?\$\$"
                     r"|(?<![\\$])\$(?![\s$])(?:\\.|[^$\\])*?(?<![\s\\])\$(?!\d)", re.S)


def strip_md_math(md):
    return MD_MATH.sub(lambda m: m.group(1) or " ", md)


def md_words(md):
    md = re.sub(r"<!--.*?-->", " ", md, flags=re.S)
    md = strip_md_math(md)  # math is not compared
    md = re.sub(r"!\[[^\]]*\]\([^)]*\)", " ", md)
    md = re.sub(r"\*\*(?:Figure|Table)\s+S?\d+[a-z]?\.\*\*", " ", md)  # LaTeX numbers floats itself
    md = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", md)
    md = re.sub(r"<https?://[^>]*>", " ", md)
    md = re.sub(r"\[@[^\]]*\]", " ", md)
    md = re.sub(r"(?<![\w@])@[a-z0-9]+", " ", md)  # narrative citations become author names
    md = re.sub(r"(?m)^\s*\d+\.\s", " ", md)  # ordered-list markers
    return tokens(md.replace("**Keywords:**", " "))


def numbers(counter):
    return Counter({t: n for t, n in counter.items() if re.search(r"\d", t)})


def pipe_table_rows(md):
    return [len(block.strip().split("\n")) - 2 for block in re.findall(r"(?m)(?:^\|.*\n?)+", md)]


def tex_table_rows(tex):
    rows = []
    for env in re.findall(r"(?s)\\begin\{(?:tabularx|tabular|xltabular)\}.*?\\end\{(?:tabularx|tabular|xltabular)\}",
                          tex):
        body = env.split("\\endfoot", 1)[1] if "\\endfoot" in env else env.split("\\hline", 2)[2]
        rows.append(len(re.findall(r"\\\\\s*$", body, flags=re.M)))
    return rows


def ieee_main_md(md):
    """The parts of the manuscript's markdown that main.tex prints, as it
    prints them: no highlights, the AI statement in the Acknowledgment."""
    parts = re.split(r"(?m)^(## .*)$", md)
    keep = []
    for head, text in zip(parts[1::2], parts[2::2]):
        if head == "## Abstract" or re.match(r"## \d", head) or head == "## Data and code availability":
            keep.append(head.replace("Conclusions", "Conclusion") + "\n" + text)
        elif head == "## Acknowledgements":
            keep.append("## Acknowledgment\n" + text)
        elif head.startswith("## Declaration of generative AI"):
            keep.append(text)
    return re.sub(r"the\s+highlights,\s+", "", "\n".join(keep))  # the IEEE version has none


def ieee_supp_md(supp, known):
    """The supplement's markdown as supplement.tex prints it: the LaTeX title
    replaces the H1, the opening names the paper, and references to the
    manuscript take IEEE numbers."""
    supp = re.sub(r"(?m)^# .*$", "", supp)
    supp = re.sub(r"Supplement to the draft manuscript \[[^\]]*\]\(manuscript\.md\)\.",
                  f"Supplement to the manuscript \u201c{p2i.TITLE_IEEE}.\u201d", supp)
    return p2i.convert_refs(supp, "supp", known)


def run_converter(argv):
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            p2i.main(argv)
    except SystemExit as e:
        raise RuntimeError(f"the converter stopped: {e}") from e


class WordHelperTests(unittest.TestCase):
    """The end-to-end word comparison ignores math on both sides alike."""

    def test_math_is_ignored_on_both_sides(self):
        md = ("a $x_1$ b\n$$\ny = 2\n$$\nc $20 and `$code$` d $3 x$ e\n\nf $20 and $3 x$ g\n\n"
              "h `$x$` i $y$ j\n\nk l m\n")
        self.assertEqual(md_words(md), Counter("a b c code d e f 20 and g h x i j k l m".split()))
        # pandoc 3.9's LaTeX for md, its display math numbered, plus a table row
        # break and an unnumbered display.
        tex = ("\\begin{document}a \\(x_1\\) b\n\\begin{equation}\ny = 2\n\\end{equation}\n"
               "c \\(20 and `\\)code\\$` d \\(3 x\\) e\n\nf \\$20 and \\(3 x\\) g\n\n"
               "h \\texttt{\\$x\\$} i \\(y\\) j\n\nk \\\\[4pt] l \\[z\\] m\\end{document}")
        self.assertEqual(tex_words(tex), md_words(md))

    def test_caption_labels_are_ignored(self):
        self.assertEqual(md_words("**Figure S1.** Cap. **Table S2a.** Tab."), Counter(["cap", "tab"]))
        tex = "\\begin{document}\\textbf{Figure S1.} Cap. \\textbf{Table S2a.} Tab.\\end{document}"
        self.assertEqual(tex_words(tex), Counter(["cap", "tab"]))


@unittest.skipUnless(PANDOC, "pandoc not available (set PANDOC=/path/to/pandoc)")
class EndToEndTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.out = Path(cls.tmp.name) / "ieee"
        run_converter([f"OUT={cls.out}", f"PANDOC={PANDOC}"])
        cls.main_tex = (cls.out / "main.tex").read_text(encoding="utf-8")
        cls.supp_tex = (cls.out / "supplement.tex").read_text(encoding="utf-8")
        cls.bib = (cls.out / "references.bib").read_text(encoding="utf-8")
        cls.main_md = ieee_main_md((ROOT / "paper/manuscript.md").read_text(encoding="utf-8"))
        cls.supp_md = ieee_supp_md((ROOT / "paper/supplement.md").read_text(encoding="utf-8"), p2i.paper_numbers())

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_figures_use_the_pdf_where_there_is_one(self):
        for line in ("\\usepackage{graphicx}", "\\usepackage{float}", "\\graphicspath{{./}{../}}"):
            self.assertIn(line, self.supp_tex)
        for tex in (self.main_tex, self.supp_tex):
            for f in p2i.graphics_files(tex):
                with self.subTest(file=f):
                    self.assertTrue((ROOT / "paper" / f).is_file())
                    if f.endswith(".png"):
                        self.assertFalse((ROOT / "paper" / f).with_suffix(".pdf").exists())
        supp = (ROOT / "paper/supplement.md").read_text(encoding="utf-8")
        captions = re.findall(r"(?m)^\*\*Figure (S\d+)\.\*\*", supp)
        self.assertEqual(re.findall(r"\\textbf\{Figure (S\d+)\.\}", self.supp_tex), captions)
        self.assertEqual(len(re.findall(r"\\begin\{figure\}", self.supp_tex)), len(captions))

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

    def test_no_bare_item_after_a_reference_list(self):
        self.assertNotRegex(self.main_tex, r"\\ref\{[^}]*\}(?:,\s*(?:and\s+|or\s+)?|\s+(?:and|or|to)\s+|--)\d")

    def test_floats_highlights_and_index_terms(self):
        self.assertEqual(len(re.findall(r"\\begin\{figure\*\}", self.main_tex)), 7)
        self.assertEqual(len(re.findall(r"\\begin\{table\*?\}", self.main_tex)), 8)
        self.assertNotRegex(self.main_tex, r"(?i)\bthe\s+highlights\b|section\*?\{highlights\}")
        self.assertIn("\\begin{IEEEkeywords}", self.main_tex)
        self.assertNotIn("longtable", self.main_tex)  # longtable fails in two-column mode
        self.assertIn("\\bstctlcite{IEEEexample:BSTcontrol}", self.main_tex)
        self.assertIn("\\usepackage[nocompress]{cite}", self.main_tex)

    def test_no_quote_damage_after_code(self):
        for tex in (self.main_tex, self.supp_tex):
            self.assertNotRegex(tex, r"\\texttt\{[^}]*\}`")

    def test_no_word_is_lost_and_every_number_matches(self):
        for name, md, tex in (("main", self.main_md, self.main_tex), ("supplement", self.supp_md, self.supp_tex)):
            with self.subTest(document=name):
                md_w, tex_w = md_words(md), tex_words(tex)
                self.assertEqual(dict(md_w - tex_w), {})
                # Numbers must match both ways, so a changed number shows up.
                self.assertEqual(dict(numbers(tex_w) - numbers(md_w)), {})
                self.assertEqual(dict(numbers(md_w) - numbers(tex_w)), {})

    def test_every_table_row_is_kept(self):
        self.assertEqual(tex_table_rows(self.main_tex), pipe_table_rows(self.main_md))
        self.assertEqual(tex_table_rows(self.supp_tex), pipe_table_rows(self.supp_md))


SYNTH_MANUSCRIPT = """# Short title

Full title: {title}.

Jane Doe. Co-authors, affiliations and the corresponding address are to be
completed.

## Highlights

- A highlight.

## Abstract

An abstract with inline math $F_1 \\geq 0$ and a citation [@kuhn1955hungarian].

**Keywords:** beta; alpha.

## 1. Introduction

The method of @kuhn1955hungarian assigns detections (Fig. 1). The dense
control is in Fig. S1, its panel (b) in Fig. S1b and both in Figs. 1 and S1.

## 2. Methods

Corrected F1 rescales F1 between the null and a perfect score:

$$
F_1^{{c}} = \\frac{{F_1 - F_1^{{0}}}}{{1 - F_1^{{0}}}}
$$

where $F_1^{{0}} \u2264 F_1$ is the F1 of 200 shifted detections (Table 1).

**Table 1.** Scores with $F_1^{{c}}$ in the head.

| Detector | $F_1^{{c}}$ |
| --- | ---: |
| A | 0.12 |

![Figure 1.](figures/figure_1.png)

**Figure 1.** Density response; panel (b) is in Fig. S1.

## CRediT authorship contribution statement

To be completed.

## Declaration of competing interest

None.

## Funding

None.

## Data and code availability

Public.

## Acknowledgements

Thanks.

## Declaration of generative AI and AI-assisted technologies in the manuscript preparation process

Claude Code drafted the text.

## References

Generated.
"""

SYNTH_SUPPLEMENT = """# Supplementary material

Supplement to the draft manuscript [Short title](manuscript.md). It refers to
Fig. 1 and Section 2.

## S1. Dense control

The control is in Fig. S1, panel (b) in Fig. S1b.

![Figure S1.](figures/figure_s1.png)

**Figure S1.** Dense control at 2 m; see Section 2 and Fig. 1.
"""


@unittest.skipUnless(PANDOC, "pandoc not available (set PANDOC=/path/to/pandoc)")
class SyntheticPaperTests(unittest.TestCase):
    """A small paper in a temporary copy of the repository layout, with a PDF
    beside a figure's PNG, a supplementary figure, display and inline math."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.tmp.cleanup)
        root = Path(cls.tmp.name)
        patcher = mock.patch.object(p2i, "REPO", root)
        patcher.start()
        cls.addClassCleanup(patcher.stop)
        (root / "docs").mkdir()
        (root / "docs/references.bib").write_text(BIB, encoding="utf-8")
        md = SYNTH_MANUSCRIPT.format(title=p2i.TITLE_IEEE.lower())
        (root / "paper/figures").mkdir(parents=True)
        (root / "paper/manuscript.md").write_text(md, encoding="utf-8")
        (root / "paper/supplement.md").write_text(SYNTH_SUPPLEMENT, encoding="utf-8")
        write_png(root / "paper/figures/figure_1.png", 50, 20)
        write_pdf(root / "paper/figures/figure_1.pdf", 360, 144)
        write_png(root / "paper/figures/figure_s1.png", 40, 40)
        write_png(root / "paper/figures/figure_9.png", 40, 40)  # not included anywhere
        run_converter([f"OUT={root / 'out'}", f"PANDOC={PANDOC}", f"ZIP={root / 'up/jstars.zip'}"])
        cls.main_tex = (root / "out/main.tex").read_text(encoding="utf-8")
        cls.supp_tex = (root / "out/supplement.tex").read_text(encoding="utf-8")
        cls.zip_names = sorted(zipfile.ZipFile(root / "up/jstars.zip").namelist())
        cls.main_md = ieee_main_md(md)
        cls.supp_md = ieee_supp_md(SYNTH_SUPPLEMENT, p2i.manuscript_numbers(md, SYNTH_SUPPLEMENT))

    def test_pdf_figure_and_zip(self):
        self.assertIn("\\includegraphics[width=\\textwidth]{figures/figure_1.pdf}", self.main_tex)
        self.assertIn("{\\centering\\includegraphics[width=0.72\\textwidth]{figures/figure_s1.png}\\par}",
                      self.supp_tex)
        self.assertEqual(self.zip_names, ["figures/figure_1.pdf", "figures/figure_s1.png", "main.tex",
                                          "references.bib", "supplement.tex"])

    def test_supplementary_figure_and_references(self):
        for line in ("\\usepackage{graphicx}", "\\usepackage{float}", "\\graphicspath{{./}{../}}"):
            self.assertIn(line, self.supp_tex)
        self.assertIn("\\begin{figure}[H]", self.supp_tex)
        self.assertIn("\\textbf{Figure S1.} Dense control at 2 m; see Section~II and Fig.~1.\n\\end{figure}",
                      self.supp_tex)
        self.assertIn("The control is in Fig.~S1, panel (b) in Fig.~S1(b).", self.supp_tex)
        self.assertNotRegex(self.supp_tex, r"\\caption|\\label")
        self.assertIn("control is in Fig.~S1, its panel (b) in Fig.~S1(b) and both in Figs.~\\ref{fig:1} and S1.",
                      self.main_tex)
        self.assertIn("\\caption{Density response; panel (b) is in Fig.~S1.}", self.main_tex)

    def test_math(self):
        self.assertIn("between the null and a perfect score:\n\\begin{equation}\n"
                      "F_1^{c} = \\frac{F_1 - F_1^{0}}{1 - F_1^{0}}\n\\end{equation}\n"
                      "where \\(F_1^{0} \\leq{} F_1\\) is the F1 of 200 shifted detections (Table~\\ref{tab:1}).",
                      self.main_tex)
        self.assertIn("An abstract with inline math \\(F_1 \\geq 0\\) and a citation~\\cite{kuhn1955hungarian}.",
                      self.main_tex)
        self.assertIn("Detector & \\(F_1^{c}\\) \\\\", self.main_tex)

    def test_no_word_is_lost_and_every_number_matches(self):
        for name, md, tex in (("main", self.main_md, self.main_tex), ("supplement", self.supp_md, self.supp_tex)):
            with self.subTest(document=name):
                md_w, tex_w = md_words(md), tex_words(tex)
                self.assertEqual(dict(md_w - tex_w), {})
                self.assertEqual(dict(numbers(tex_w) - numbers(md_w)), {})
                self.assertEqual(dict(numbers(md_w) - numbers(tex_w)), {})
                self.assertEqual(tex_table_rows(tex), pipe_table_rows(md))


@unittest.skipUnless(BIBTEX, "bibtex not available (set BIBTEX=/path/to/bibtex)")
class BibtexTests(unittest.TestCase):
    """Run IEEEtran.bst on the IEEE copy of the whole bibliography."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        out = Path(cls.tmp.name)
        cls.source = (ROOT / "docs/references.bib").read_text(encoding="utf-8")
        (out / "references.bib").write_text(p2i.ieee_bib(cls.source), encoding="utf-8")
        (out / "all.aux").write_text("\\relax\n\\citation{IEEEexample:BSTcontrol}\n\\citation{*}\n"
                                     "\\bibstyle{IEEEtran}\n\\bibdata{references}\n")
        cls.proc = subprocess.run([BIBTEX, "all"], cwd=out, capture_output=True, text=True)
        cls.blg = (out / "all.blg").read_text()
        cls.bbl = (out / "all.bbl").read_text()
        cls.items = {m.group(1): flat(m.group(2)) for m in
                     re.finditer(r"(?s)\\bibitem\{([^}]*)\}(.*?)(?=\\bibitem\{|\\end\{thebibliography\})", cls.bbl)}

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_bibtex_runs_clean(self):
        self.assertEqual(self.proc.returncode, 0, self.proc.stdout + self.proc.stderr)
        self.assertNotIn("Warning--", self.blg)

    def test_bibtex_prints_the_mapped_fields(self):
        bbl = flat(self.bbl)
        for text in ("3-{D}", "{Mill.}", "{MIT} licence", "{R} package", "Zenodo", "The R Foundation",
                     "version RELEASE-2026", "commit 5380ddec", "arXiv:2010.16061", "arXiv:2108.13264",
                     "`equitable threat score'"):
            self.assertIn(text, bbl)
        for text in ("mIT", " r package", "3-d ", "mill.)", "Undated page", "------"):
            self.assertNotIn(text, bbl)
        self.assertNotRegex(bbl, r"[,.] accessed:")
        dated = [k for _, k, f, _ in p2i.parse_bib(self.source) if "urldate" in dict(f)]
        for key in dated:
            self.assertRegex(self.items[key], r"(?:\{A\}|A)ccessed: Oct\. 2, 2026", key)
        # IEEE cites the version of record: the DOI, not the arXiv identifier.
        self.assertIn("doi:", self.items["hamraz2016robust"])
        self.assertNotIn("1701.00198", self.items["hamraz2016robust"])
        # More than six authors: the first author and et al.
        self.assertRegex(self.items["yates2018outstanding"], r"et~al\.")
        self.assertLess(self.items["yates2018outstanding"].count(" and "), 1)


if __name__ == "__main__":
    unittest.main()
