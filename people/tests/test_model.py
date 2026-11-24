"""Made-up people only."""
import unittest

from good_input_people.model import Decisions, agree, resolve, tokens
from good_input_people.vcard import parse, phone


def cards(*specs):
    text = ""
    for name, *lines in specs:
        text += "BEGIN:VCARD\nVERSION:2.1\nFN:%s\n%s\nEND:VCARD\n" % (name, "\n".join(lines))
    return parse(text, "phone", "t")


def names(res):
    return sorted(sorted(res.records[i].name for i in p.records) for p in res.people)


class Phone(unittest.TestCase):
    def test_one_number_many_spellings(self):
        for s in ("612-555-0100", "(612) 555-0100", "+1-612-555-0100", "1 612 555 0100", "+16125550100",
                  "612.555.0100 x12"):
            self.assertEqual(phone(s), "+16125550100", s)

    def test_short_and_foreign(self):
        self.assertEqual(phone("555-0100"), "local:5550100")
        self.assertEqual(phone("+44 20 7946 0958"), "+442079460958")
        self.assertEqual(phone("011 44 20 7946 0958"), "+442079460958")


class Cards(unittest.TestCase):
    def test_quoted_printable_and_types(self):
        (r,) = parse("BEGIN:VCARD\nVERSION:2.1\nFN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:Jos=C3=A9 =\nRuiz\n"
                     "TEL;CELL;PREF:612-555-0100\nEMAIL;PREF;HOME:Jose@Example.com\n"
                     "PHOTO;ENCODING=BASE64;JPEG:AAAA\n AAAA\n\nX-KDECONNECT-ID-DEV-abc:77\nEND:VCARD\n", "phone")
        self.assertEqual(r.name, "José Ruiz")
        self.assertEqual([h.key for h in r.handles], ["tel:+16125550100", "email:jose@example.com"])
        self.assertTrue(r.handles[0].personal)
        self.assertEqual(r.id, "77")


class Names(unittest.TestCase):
    def test_agree(self):
        self.assertTrue(agree("Ana", "Ana Reyes"))
        self.assertTrue(agree("REYES, Ana", "Ana Reyes"))
        self.assertTrue(agree("José Ruiz", "Jose Ruiz 🎸"))
        self.assertFalse(agree("Mom", "Jane Doe"))
        self.assertEqual(tokens("Ana (work)"), ("ana",))


class Joining(unittest.TestCase):
    def test_same_number_same_name_joins(self):
        res = resolve(cards(("Ana Reyes", "TEL;CELL:612-555-0100"), ("Ana Reyes", "TEL;CELL:+1 612 555 0100"),
                            ("Ben Ode", "TEL;CELL:612-555-0111")))
        self.assertEqual(names(res), [["Ana Reyes", "Ana Reyes"], ["Ben Ode"]])
        self.assertEqual(res.people[0].joins[0].reason, "same-handle")

    def test_same_mobile_different_name_joins(self):
        res = resolve(cards(("Mom", "TEL;CELL:612-555-0100"), ("Jane Doe", "TEL;CELL:612-555-0100")))
        self.assertEqual(len(res.people), 1)
        self.assertEqual(res.people[0].name, "Jane Doe")
        self.assertEqual(res.people[0].joins[0].reason, "same-handle")

    def test_family_landline_joins_nobody(self):
        res = resolve(cards(("Mom", "TEL;HOME:612-555-0100"), ("Dad", "TEL;HOME:612-555-0100")))
        self.assertEqual(len(res.people), 2)
        self.assertIn("tel:+16125550100", res.shared)
        self.assertEqual(res.suggestions[0].reason, "shared-handle")

    def test_unknown_kind_different_names_joins_nobody(self):
        res = resolve(cards(("Front Desk", "TEL:612-555-0100"), ("Cy Vance", "TEL:612-555-0100")))
        self.assertEqual(len(res.people), 2)

    def test_office_mailbox_joins_nobody(self):
        res = resolve(cards(("Ana Reyes", "EMAIL:info@shop.example"), ("Ben Ode", "EMAIL:info@shop.example")))
        self.assertEqual(len(res.people), 2)

    def test_mobile_on_three_cards_with_three_names_is_shared(self):
        res = resolve(cards(("A One", "TEL;CELL:612-555-0100"), ("B Two", "TEL;CELL:612-555-0100"),
                            ("C Three", "TEL;CELL:612-555-0100")))
        self.assertEqual(len(res.people), 3)

    def test_chain_through_two_handles(self):
        res = resolve(cards(("Ana Reyes", "TEL;CELL:612-555-0100"),
                            ("Ana Reyes", "TEL;CELL:612-555-0100", "EMAIL:ana@example.com"),
                            ("Ana", "EMAIL:ana@example.com")))
        self.assertEqual(len(res.people), 1)
        self.assertEqual(len(res.people[0].handles), 2)

    def test_same_name_is_only_a_suggestion(self):
        res = resolve(cards(("Ana Reyes", "TEL;CELL:612-555-0100"), ("Ana Reyes", "TEL;CELL:612-555-0199"),
                            ("Sam", "TEL;CELL:612-555-0101"), ("Sam", "TEL;CELL:612-555-0102")))
        self.assertEqual(len(res.people), 4)
        self.assertEqual([(s.reason, s.strength) for s in res.suggestions],
                         [("same-name", "strong"), ("same-first-name", "weak")])


class ByHand(unittest.TestCase):
    two = (("Ana Reyes", "TEL;CELL:612-555-0100"), ("A. R.", "TEL;CELL:612-555-0199"))

    def test_join_by_hand(self):
        res = resolve(cards(*self.two), Decisions(joins=[("tel:+16125550100", "tel:+16125550199")]))
        self.assertEqual(len(res.people), 1)
        self.assertEqual(res.people[0].joins[0].reason, "hand")

    def test_split_by_hand_is_never_rejoined_or_offered_again(self):
        recs = cards(("Ana Reyes", "TEL;CELL:612-555-0100", "EMAIL:shared@example.com"),
                     ("Ana Reyes", "TEL;CELL:612-555-0199", "EMAIL:shared@example.com"))
        self.assertEqual(len(resolve(recs).people), 1)
        res = resolve(recs, Decisions(splits=[("tel:+16125550100", "tel:+16125550199")]))
        self.assertEqual(len(res.people), 2)
        self.assertEqual(len(res.blocked), 1)
        self.assertEqual(res.suggestions, [])

    def test_rebuild_gives_the_same_people(self):
        d = Decisions(joins=[("tel:+16125550100", "tel:+16125550199")])
        self.assertEqual(names(resolve(cards(*self.two), d)), names(resolve(list(reversed(cards(*self.two))), d)))


if __name__ == "__main__":
    unittest.main()
