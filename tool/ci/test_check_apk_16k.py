import unittest

from check_apk_16k import check_load_segments


class CheckLoadSegmentsTest(unittest.TestCase):
    def test_requires_all_segments_to_align(self):
        output = '''  LOAD 0x000000 0x000000 0x000000 0x10 0x10 R 0x4000
  LOAD 0x004000 0x004000 0x004000 0x10 0x10 R E 0x1000'''
        self.assertEqual(len(check_load_segments(output, 'x.so')), 1)

    def test_accepts_larger_page_alignment(self):
        self.assertEqual(check_load_segments('  LOAD 0x00 0x00 0x00 0x10 0x10 R 0x10000', 'x.so'), [])

    def test_rejects_missing_or_unparseable_segments(self):
        self.assertTrue(check_load_segments('', 'x.so'))
        self.assertTrue(check_load_segments('  LOAD bad', 'x.so'))


if __name__ == '__main__':
    unittest.main()
