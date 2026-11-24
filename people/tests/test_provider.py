"""The provider's answers, over made-up cards in a temporary home."""
import os
import tempfile
import unittest
from pathlib import Path

from good_input_people import provider

CARDS = {
    "1": ("Ana Reyes", "TEL;CELL:612-555-0100"),
    "2": ("Ana Reyes", "TEL;CELL:612-555-0100", "EMAIL:ana@example.com"),
    "3": ("Ana Reyes", "TEL;CELL:612-555-0199"),
    "4": ("Ben Okafor", "TEL;HOME:612-555-0111"),
    "5": ("Joanna Lind", "TEL;CELL:612-555-0122"),
}


class Provider(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.TemporaryDirectory()
        os.environ["XDG_DATA_HOME"] = self.home.name
        os.environ.pop("GOOD_INPUT_PEOPLE_CARDS", None)
        folder = Path(self.home.name) / "kpeoplevcard" / "kdeconnect-test"
        folder.mkdir(parents=True)
        for ident, (name, *lines) in CARDS.items():
            (folder / f"{ident}.vcf").write_text(
                "BEGIN:VCARD\nVERSION:2.1\nFN:%s\n%s\nX-KDECONNECT-ID-DEV-test:%s\nEND:VCARD\n"
                % (name, "\n".join(lines), ident))

    def tearDown(self):
        self.home.cleanup()

    def test_everyone_once_by_name(self):
        got = provider.answer(["people"])
        self.assertEqual(got["count"], 4)
        self.assertEqual([p["name"] for p in got["people"]], ["Ana Reyes", "Ana Reyes", "Ben Okafor", "Joanna Lind"])
        self.assertEqual(got["people"][0]["summary"], "1 number · 1 address")
        self.assertEqual(got["people"][0]["initials"], "AR")

    def test_a_long_list_is_never_cut_short(self):
        folder = Path(self.home.name) / "kpeoplevcard" / "kdeconnect-test"
        for n in range(300):
            (folder / f"many{n}.vcf").write_text(
                "BEGIN:VCARD\nVERSION:2.1\nFN:Person %03d\nTEL;CELL:612-556-%04d\nEND:VCARD\n" % (n, n))
        got = provider.answer(["people"])
        self.assertEqual(got["count"], 304)
        self.assertEqual(len(got["people"]), 304)
        self.assertEqual(got["people"][-1]["name"], "Person 299")

    def test_words_find_by_name_start_number_and_address(self):
        names = lambda *a: [p["name"] for p in provider.answer(["people", *a])["people"]]
        self.assertEqual(names("an"), ["Ana Reyes", "Ana Reyes"])
        self.assertEqual(names("lind"), ["Joanna Lind"])
        self.assertEqual(names("0111"), ["Ben Okafor"])
        self.assertEqual(names("ana@example"), ["Ana Reyes"])
        self.assertEqual(names("zz"), [])

    def test_person_page(self):
        p = provider.answer(["person", "1"])
        self.assertEqual([h["shown"] for h in p["handles"]], ["(612) 555-0100", "ana@example.com"])
        self.assertEqual([h["label"] for h in p["handles"]], ["Mobile", "Email"])
        self.assertEqual((p["cards"], p["joined"]), (2, "same"))
        self.assertEqual((p["match"]["id"], p["match"]["why"]), ("3", "name"))
        self.assertEqual(provider.answer(["person", "nobody"]), {"error": "gone"})

    def test_join_then_separate(self):
        p = provider.answer(["join", "1", "3"])
        self.assertEqual((p["cards"], p["joined"], p["match"]), (3, "hand", None))
        self.assertEqual(provider.answer(["people"])["count"], 3)
        p = provider.answer(["separate", "1"])
        self.assertEqual(p["cards"], 1)
        self.assertEqual(provider.answer(["people"])["count"], 5)
        # Taken apart by hand, the cards that share a number stay apart.
        self.assertEqual(provider.answer(["person", "2"])["cards"], 1)
        # And joining two of them again by hand holds.
        self.assertEqual(provider.answer(["join", "1", "2"])["cards"], 2)

    def test_not_the_same_is_not_asked_again(self):
        p = provider.answer(["not-same", "1", "3"])
        self.assertIsNone(p["match"])
        self.assertIsNone(provider.answer(["person", "3"])["match"])
        self.assertEqual(provider.answer(["people"])["count"], 4)

    def test_choices_count_then_start_over_forgets_them(self):
        got = provider.answer(["choices"])
        self.assertEqual((got["cards"], got["joined"], got["apart"]), (5, 0, 0))
        ana = provider.answer(["people", "ana"])["people"]
        provider.answer(["join", ana[0]["id"], ana[1]["id"]])
        ben = provider.answer(["people", "ben"])["people"][0]["id"]
        joanna = provider.answer(["people", "joanna"])["people"][0]["id"]
        provider.answer(["not-same", ben, joanna])
        got = provider.answer(["choices"])
        self.assertEqual((got["joined"], got["apart"], got["people"]), (1, 1, 3))
        got = provider.answer(["start-over"])
        self.assertEqual((got["cards"], got["joined"], got["apart"], got["people"]), (5, 0, 0, 4))
        self.assertEqual(provider.answer(["people"])["count"], 4)

    def test_unreadable_decisions_start_empty(self):
        provider.decisions_file().parent.mkdir(parents=True)
        provider.decisions_file().write_text("{nonsense")
        self.assertEqual(provider.answer(["people"])["count"], 4)


if __name__ == "__main__":
    unittest.main()
