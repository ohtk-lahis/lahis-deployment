import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import unittest


class WorkerHealthTests(unittest.TestCase):
    def probe(self, replies):
        helper = Path(__file__).resolve().parents[1] / 'scripts/lib/common.sh'
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory) / 'podd_api'
            package.mkdir()
            (package / '__init__.py').write_text('')
            (package / 'celery.py').write_text('''import json, os, socket
class Control:
    def ping(self, destination, timeout):
        assert destination == ['celery@' + socket.gethostname()]
        assert timeout == 5
        return json.loads(os.environ['TEST_WORKER_REPLIES'])
class App:
    control = Control()
app = App()
''')
            environment = {**os.environ, 'PYTHONPATH': directory,
                           'TEST_WORKER_REPLIES': json.dumps(replies)}
            # Run the production probe with only Docker execution substituted.
            command = '''source "$1"
compose() {
  [[ "$1 $2 $3" == "exec -T celery" ]] || return 99
  shift 3
  "$@"
}
celery_running_ok
'''
            return subprocess.run(['bash', '-c', command, 'probe', str(helper)],
                                  env=environment, capture_output=True).returncode

    def test_local_worker_pong_passes(self):
        self.assertEqual(0, self.probe([{'celery@' + socket.gethostname(): {'ok': 'pong'}}]))

    def test_running_but_unresponsive_worker_fails(self):
        self.assertNotEqual(0, self.probe([]))

    def test_another_workers_pong_does_not_pass(self):
        self.assertNotEqual(0, self.probe([{'celery@another-container': {'ok': 'pong'}}]))


if __name__ == '__main__':
    unittest.main()
