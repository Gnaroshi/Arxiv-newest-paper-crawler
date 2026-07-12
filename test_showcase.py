import unittest

from webapp import app, showcase_enabled


class ShowcaseBoundaryTests(unittest.TestCase):
    def test_normal_execution_does_not_enable_showcase(self):
        self.assertFalse(showcase_enabled({}))

    def test_showcase_requires_explicit_flag(self):
        self.assertTrue(showcase_enabled({"GNAROSHI_SHOWCASE": "1"}))


if __name__ == "__main__":
    unittest.main()
