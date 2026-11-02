from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import tempfile
from threading import Barrier
import unittest

from outbox import Outbox


ACTION = {"device": "device-a", "sequence": 1, "context": {"device-a": 0, "device-b": 0},
          "record": "bookmark", "kind": "put", "value": {"position_ms": 12000}}


class PendingActions(unittest.TestCase):
    def test_a_new_database_is_claimed_by_only_one_concurrent_account(self):
        with tempfile.TemporaryDirectory() as directory:
            for trial in range(12):
                path = Path(directory) / f"claim-{trial}.sqlite"
                barrier = Barrier(8)

                def claim(number):
                    barrier.wait(timeout=10)
                    try:
                        box = Outbox(path, "server-one", f"account-{number}", "device-a")
                    except PermissionError:
                        return False
                    box.close()
                    return True

                with ThreadPoolExecutor(max_workers=8) as accounts:
                    claims = list(accounts.map(claim, range(8)))
                self.assertEqual(sum(claims), 1, "Exactly one account must own a new pending-action database")

    def test_a_pending_action_survives_closing_and_reopening_its_account(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "outbox.sqlite"
            first = Outbox(path, "server-one", "alice", "device-a")
            first.enqueue(ACTION)
            first.close()
            reopened = Outbox(path, "server-one", "alice", "device-a")
            self.addCleanup(reopened.close)
            self.assertEqual(reopened.pending(), [ACTION])

    def test_another_account_cannot_open_the_pending_actions(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "outbox.sqlite"
            first = Outbox(path, "server-one", "alice", "device-a")
            first.enqueue(ACTION)
            first.close()
            for scope in (("server-two", "alice", "device-a"), ("server-one", "bob", "device-a"),
                          ("server-one", "alice", "device-b")):
                with self.assertRaises(PermissionError):
                    Outbox(path, *scope)

    def test_an_action_identity_cannot_silently_change_while_offline(self):
        with tempfile.TemporaryDirectory() as directory:
            box = Outbox(Path(directory) / "outbox.sqlite", "server-one", "alice", "device-a")
            self.addCleanup(box.close)
            box.enqueue(ACTION)
            with self.assertRaises(ValueError):
                box.enqueue({**ACTION, "value": {"position_ms": 9000}})
            self.assertEqual(box.pending(), [ACTION])


if __name__ == "__main__":
    unittest.main(verbosity=2)
