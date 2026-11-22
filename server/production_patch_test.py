"""Exercise the global-country patch against temporary Laravel file fixtures."""
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PATCH = ROOT / 'production-patches/jobs_20261103_global'


@unittest.skipUnless(shutil.which('php'), 'PHP is required for patch checks')
class GlobalPatchTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name) / 'laravel'
        self.backup = Path(self.temp.name) / 'backup'
        self.base.mkdir()
        (self.base / 'artisan').write_text('<?php\n')
        routes = self.base / 'routes/api.php'
        routes.parent.mkdir()
        routes.write_text('<?php\n')
        snapshots = {
            'app/Support/JobValues.php': 'jobs_20261009',
            'app/Http/Controllers/Api/JobController.php': 'jobs_20261010',
        }
        for file, release in snapshots.items():
            target = self.base / file
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / 'production-patches' / release / file, target)
        for view in ['create', 'edit']:
            target = self.base / f'resources/views/dashboard/job/{view}.blade.php'
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('<input name="country" value="سوريا" readonly>\n<select name="state"><option>دمشق</option></select>')

    def run_patch(self):
        return subprocess.run(['php', str(PATCH / 'apply.php'), str(self.base), str(self.backup)], capture_output=True, text=True)

    def snapshot(self):
        return {str(path.relative_to(self.base)): path.read_bytes() for path in self.base.rglob('*') if path.is_file()}

    def test_apply_preserves_dashboard_values_and_adds_public_city_route(self):
        result = self.run_patch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('JobLocationController', (self.base / 'routes/api.php').read_text())
        form = (self.base / 'resources/views/dashboard/job/edit.blade.php').read_text()
        self.assertIn('JobValues::countryNames()', form)
        self.assertIn("$job->country", form)
        self.assertIn('maxlength="100"', form)
        self.assertNotIn('readonly', form)
        self.assertTrue((self.backup / 'manifest.json').is_file())

    def test_unexpected_controller_is_rejected_before_any_changes(self):
        controller = self.base / 'app/Http/Controllers/Api/JobController.php'
        controller.write_text(controller.read_text() + '\n// A newer production change\n')
        before = self.snapshot()
        self.assertNotEqual(self.run_patch().returncode, 0)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(self.backup.exists())

    def test_unexpected_dashboard_rolls_back_all_touched_files(self):
        (self.base / 'resources/views/dashboard/job/edit.blade.php').write_text('A customized form')
        before = self.snapshot()
        self.assertNotEqual(self.run_patch().returncode, 0)
        self.assertEqual(self.snapshot(), before)


if __name__ == '__main__':
    unittest.main()
