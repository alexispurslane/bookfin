import json
import unittest

from finite_journal import Journal, cleanup_plan, covered_batches, discover


def operation(device, sequence, context, record="bookmark", kind="put", value="synthetic"):
    return {"device": device, "sequence": sequence, "context": context,
            "record": record, "kind": kind, "value": value if kind == "put" else None}


def journal_with(*actions):
    journal = Journal()
    journal.receive(actions)
    return journal


class FiniteJournalTests(unittest.TestCase):
    def test_the_on_demand_invariant_checker_rejects_a_covered_pending_action(self):
        action = operation("device-a", 1, {"device-a": 0, "device-b": 0})
        journal = journal_with(action)
        journal.pending[("device-a", 1)] = action
        with self.assertRaises(AssertionError):
            journal.check_invariants()

    def test_concurrent_cleaners_keep_the_same_equivalent_checkpoint(self):
        journal = journal_with(operation("device-a", 1, {"device-a": 0, "device-b": 0}))
        checkpoints = [("a", {"state": journal.checkpoint()}), ("b", {"state": journal.checkpoint()})]
        self.assertEqual(cleanup_plan(journal, [], checkpoints), ("a", ["b"]))
        self.assertEqual(cleanup_plan(journal, [], list(reversed(checkpoints))), ("a", ["b"]))

    def test_a_stale_checkpoint_cannot_authorize_deleting_a_newer_checkpoint(self):
        old = journal_with(operation("device-a", 1, {"device-a": 0, "device-b": 0}))
        new = Journal(old.checkpoint())
        new.receive([operation("device-a", 2, {"device-a": 1, "device-b": 0}, value="new")])
        checkpoints = [("old", {"state": old.checkpoint()}), ("new", {"state": new.checkpoint()})]
        self.assertEqual(cleanup_plan(old, [], checkpoints), ("old", []))

    def test_discovery_joins_checkpoints_before_replaying_old_batches(self):
        birth = operation("device-a", 1, {"device-a": 0, "device-b": 0})
        deleted = journal_with(birth, operation("device-a", 2,
            {"device-a": 1, "device-b": 0}, kind="delete"))
        items = [{"Id": "batch", "Name": json.dumps({"namespace": "finite", "kind": "batch", "operations": [birth]})},
                 {"Id": "checkpoint", "Name": json.dumps({"namespace": "finite", "kind": "checkpoint",
                                                          "state": deleted.checkpoint()})}]
        state, batches, checkpoints = discover(items, "finite")
        self.assertEqual(state.deletion_count, 1)
        self.assertEqual(state.values("bookmark"), [])
        self.assertEqual(covered_batches(state, batches), ["batch"])
        self.assertEqual(len(checkpoints), 1)

    def test_cleanup_keeps_an_entire_batch_until_every_action_is_covered(self):
        earlier = operation("device-a", 1, {"device-a": 0, "device-b": 0})
        later = operation("device-a", 2, {"device-a": 1, "device-b": 0})
        batches = [("mixed", {"operations": [earlier, later]}), ("earlier", {"operations": [earlier]})]
        self.assertEqual(covered_batches(journal_with(earlier), batches), ["earlier"])

    def test_a_missing_earlier_action_does_not_become_checkpoint_coverage(self):
        journal = journal_with(operation("device-a", 2, {"device-a": 1, "device-b": 0}))
        restored = Journal(journal.checkpoint())
        self.assertEqual(restored.coverage, {"device-a": 0, "device-b": 0})
        self.assertEqual(restored.values("bookmark"), [])
        self.assertEqual(restored.pending_count, 1)

    def test_merging_the_missing_action_releases_the_buffered_later_action(self):
        first = journal_with(operation("device-a", 2, {"device-a": 1, "device-b": 0}, value="later"))
        second = journal_with(operation("device-a", 1, {"device-a": 0, "device-b": 0}, value="earlier"))
        first.merge(second.checkpoint())
        self.assertEqual(first.coverage, {"device-a": 2, "device-b": 0})
        self.assertEqual(first.values("bookmark"), ["later"])
        self.assertEqual(first.pending_count, 0)

    def test_concurrent_checkpoints_preserve_both_unresolved_edits(self):
        base = journal_with(operation("device-a", 1, {"device-a": 0, "device-b": 0}))
        first, second = Journal(base.checkpoint()), Journal(base.checkpoint())
        first.receive([operation("device-a", 2, {"device-a": 1, "device-b": 0}, value="first")])
        second.receive([operation("device-b", 1, {"device-a": 1, "device-b": 0}, value="second")])
        forward, reverse = Journal(first.checkpoint()), Journal(second.checkpoint())
        forward.merge(second.checkpoint())
        reverse.merge(first.checkpoint())
        self.assertEqual(forward.values("bookmark"), ["first", "second"])
        self.assertEqual(forward.checkpoint(), reverse.checkpoint())
        forward.merge(first.checkpoint())
        self.assertEqual(forward.checkpoint(), reverse.checkpoint())

    def test_a_causal_edit_replaces_only_the_versions_it_observed(self):
        journal = journal_with(operation("device-a", 1, {"device-a": 0, "device-b": 0}),
            operation("device-b", 1, {"device-a": 1, "device-b": 0}, value="revised"))
        self.assertEqual(journal.values("bookmark"), ["revised"])

    def test_a_delete_survives_checkpoint_cleanup_and_a_delayed_covered_retry(self):
        birth = operation("device-a", 1, {"device-a": 0, "device-b": 0})
        deletion = operation("device-b", 1, {"device-a": 1, "device-b": 0}, kind="delete")
        restored = Journal(journal_with(birth, deletion).checkpoint())
        restored.receive([birth])
        self.assertEqual(restored.values("bookmark"), [])
        self.assertEqual(restored.deletion_count, 1)
        restored.merge(journal_with(birth).checkpoint())
        self.assertEqual(restored.values("bookmark"), [])

    def test_a_delete_does_not_silently_resolve_a_concurrent_edit(self):
        journal = journal_with(operation("device-a", 1, {"device-a": 0, "device-b": 0}),
            operation("device-a", 2, {"device-a": 1, "device-b": 0}, kind="delete"),
            operation("device-b", 1, {"device-a": 1, "device-b": 0}, value="offline edit"))
        self.assertEqual(journal.values("bookmark"), ["offline edit"])
        self.assertEqual(journal.deletion_count, 1)
        self.assertEqual(journal.conflict_count, 1)

    def test_an_unseen_other_device_dependency_blocks_checkpoint_coverage(self):
        journal = journal_with(operation("device-b", 1, {"device-a": 1, "device-b": 0}))
        self.assertEqual(journal.coverage, {"device-a": 0, "device-b": 0})
        journal.receive([operation("device-a", 1, {"device-a": 0, "device-b": 0})])
        self.assertEqual(journal.coverage, {"device-a": 1, "device-b": 1})

    def test_reordered_duplicate_delivery_and_checkpoint_join_have_the_same_result(self):
        birth = operation("device-a", 1, {"device-a": 0, "device-b": 0})
        first = operation("device-a", 2, {"device-a": 1, "device-b": 0}, value="first")
        second = operation("device-b", 1, {"device-a": 1, "device-b": 0}, value="second")
        self.assertEqual(journal_with(second, first, second, birth, first).checkpoint(),
                         journal_with(birth, first, second).checkpoint())

    def test_a_third_identity_is_rejected_instead_of_expiring_an_existing_identity(self):
        with self.assertRaises(ValueError):
            journal_with(operation("device-c", 1, {"device-a": 0, "device-b": 0}))

    def test_each_deleted_record_keeps_a_deletion_witness_in_this_candidate(self):
        journal = Journal()
        for sequence in range(1, 41):
            journal.receive([operation("device-a", sequence,
                {"device-a": sequence - 1, "device-b": 0}, f"bookmark-{(sequence - 1) // 2}",
                kind="put" if sequence % 2 else "delete")])
        self.assertEqual(journal.deletion_count, 20)
        self.assertEqual(len(journal.checkpoint()["records"]), 20)
