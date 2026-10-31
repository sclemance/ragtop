"""Index reuse must not hide a real layout/language change or poison a valid one."""
import copy
import unittest
from predictor import Swipes


class Geometry(unittest.TestCase):
    def setUp(self):
        self.decoder = Swipes({'cat': 100, 'at': 200, 'act': 300})
        self.geometry = {'unit': 1, 'keys': {'c': [0, 0], 'a': [1, 0], 't': [2, 0]}}
        self.decoder.set_keys(self.geometry)

    def test_duplicate_reuses_index_and_answers(self):
        d = self.decoder
        ends, lengths = d.ends, d.lengths
        answer = d.decode([[0, 0], [1, 0], [2, 0]])
        equivalent = {'keys': dict(reversed(list(self.geometry['keys'].items()))), 'unit': 1.0}
        d.set_keys(equivalent)
        self.assertIs(d.ends, ends)
        self.assertIs(d.lengths, lengths)
        self.assertEqual(answer, d.decode([[0, 0], [1, 0], [2, 0]]))

    def test_changes_rebuild_like_fresh_decoder(self):
        for change in ['unit', 'position', 'letter', 'empty']:
            g = copy.deepcopy(self.geometry)
            if change == 'unit': g['unit'] = 2
            elif change == 'position': g['keys']['t'] = [3, 1]
            elif change == 'letter': g['keys'].pop('c')
            else: g['keys'] = {}
            old = self.decoder.lengths
            self.decoder.set_keys(g)
            fresh = Swipes(self.decoder.ranks)
            fresh.set_keys(g)
            self.assertIsNot(old, self.decoder.lengths)
            self.assertEqual(fresh.ends, self.decoder.ends)
            self.assertEqual(fresh.lengths, self.decoder.lengths)
            self.decoder.set_keys(self.geometry)

    def test_each_language_initializes_independently(self):
        other = Swipes({'at': 100})
        other.set_keys(self.geometry)
        self.assertEqual(set(other.lengths), {'at'})
        self.assertEqual(set(self.decoder.lengths), {'cat', 'at', 'act'})

    def test_malformed_updates_preserve_working_geometry(self):
        d = self.decoder
        original = (d.keys, d.ends, d.lengths, d.unit)
        bad = [None, {}, {'unit': float('nan'), 'keys': {}},
               {'unit': True, 'keys': {}}, {'unit': -1, 'keys': {}},
               {'unit': 1, 'keys': {'c': [1, float('inf')]}},
               {'unit': 1, 'keys': {'c': ['1', 2]}},
               {'unit': 1, 'keys': {'c': [1]}}]
        for geometry in bad:
            d.set_keys(geometry)
            self.assertEqual(original, (d.keys, d.ends, d.lengths, d.unit))
            self.assertIs(d.lengths, original[2])


if __name__ == '__main__': unittest.main()
