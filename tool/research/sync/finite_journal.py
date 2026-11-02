import copy
import json


DEVICES = ("device-a", "device-b")


def discover(items, namespace):
    journal, batches, checkpoints = Journal(), [], []
    for item in items:
        try:
            payload = json.loads(item["Name"])
        except (KeyError, TypeError, json.JSONDecodeError):
            continue
        if not isinstance(payload, dict) or payload.get("namespace") != namespace:
            continue
        if payload.get("kind") == "checkpoint":
            journal.merge(payload["state"])
            checkpoints.append((item["Id"], payload))
        elif payload.get("kind") == "batch":
            batches.append((item["Id"], payload))
        else:
            raise ValueError("Unrecognized object in the finite research namespace")
    for _, batch in batches:
        journal.receive(batch["operations"])
    journal.check_invariants()
    return journal, batches, checkpoints


def covered_batches(journal, batches):
    return [identifier for identifier, batch in batches
            if batch["operations"] and all(action["sequence"] <= journal.coverage[action["device"]]
                                           for action in batch["operations"])]


def cleanup_plan(journal, batches, checkpoints):
    equivalent = [identifier for identifier, payload in checkpoints
                  if Journal(payload["state"]).checkpoint() == journal.checkpoint()]
    if not equivalent:
        raise ValueError("Cleanup requires a durably published equivalent checkpoint")
    keep = min(equivalent)
    removable = covered_batches(journal, batches)
    for identifier, payload in checkpoints:
        if identifier == keep:
            continue
        joined = Journal(journal.checkpoint())
        joined.merge(payload["state"])
        if joined.checkpoint() == journal.checkpoint():
            removable.append(identifier)
    return keep, sorted(removable)


def dot(action):
    return action["device"], action["sequence"]


def validate_vector(vector):
    if set(vector) != set(DEVICES) or any(type(count) is not int or count < 0 for count in vector.values()):
        raise ValueError("Coverage must contain nonnegative counts for the two research identities")


def validate_action(action):
    if action["device"] not in DEVICES or type(action["sequence"]) is not int or action["sequence"] < 1:
        raise ValueError("Actions require a fixed research identity and a positive sequence")
    validate_vector(action["context"])
    if action["context"][action["device"]] != action["sequence"] - 1:
        raise ValueError("An author must include its complete earlier action prefix")
    if not isinstance(action["record"], str) or not action["record"] or action["kind"] not in ("put", "delete"):
        raise ValueError("Actions require a record and a put or delete kind")
    if action["kind"] == "delete" and action["value"] is not None:
        raise ValueError("Deletion has no live value")


class Journal:
    def __init__(self, checkpoint=None):
        self.coverage = {"device-a": 0, "device-b": 0}
        self.records = {}
        self.pending = {}
        if checkpoint is not None:
            self.merge(checkpoint)

    def checkpoint(self):
        return copy.deepcopy({"coverage": dict(self.coverage),
            "records": {record: [versions[identity] for identity in sorted(versions)]
                        for record, versions in sorted(self.records.items())},
            "pending": [self.pending[identity] for identity in sorted(self.pending)]})

    def receive(self, operations):
        for action in operations:
            validate_action(action)
            identity = dot(action)
            if action["sequence"] <= self.coverage[action["device"]]:
                continue
            if identity in self.pending and self.pending[identity] != action:
                raise ValueError("An immutable action identity has conflicting payloads")
            self.pending[identity] = copy.deepcopy(action)
        self._drain()

    def _drain(self):
        while True:
            ready = next((identity for identity, action in sorted(self.pending.items())
                if action["sequence"] == self.coverage[action["device"]] + 1
                and all(count <= self.coverage[device] for device, count in action["context"].items())), None)
            if ready is None:
                return
            action = self.pending.pop(ready)
            versions = self.records.get(action["record"], {})
            self.records[action["record"]] = {
                identity: version for identity, version in versions.items()
                if identity[1] > action["context"][identity[0]]}
            self.records[action["record"]][ready] = action
            self.coverage[action["device"]] = action["sequence"]

    def merge(self, checkpoint):
        incoming_coverage = checkpoint["coverage"]
        validate_vector(incoming_coverage)
        incoming_records = {}
        for record, actions in checkpoint["records"].items():
            versions = {}
            for action in actions:
                validate_action(action)
                if action["record"] != record or action["sequence"] > incoming_coverage[action["device"]]:
                    raise ValueError("Checkpoint values must be covered and use their record key")
                if any(count > incoming_coverage[device] for device, count in action["context"].items()):
                    raise ValueError("Checkpoint coverage must contain every value dependency")
                identity = dot(action)
                if identity in versions and versions[identity] != action:
                    raise ValueError("An immutable action identity has conflicting payloads")
                versions[identity] = copy.deepcopy(action)
            incoming_records[record] = versions
        joined = {}
        for record in self.records.keys() | incoming_records.keys():
            local = self.records.get(record, {})
            remote = incoming_records.get(record, {})
            versions = {}
            for identity in local.keys() | remote.keys():
                if identity in local and identity in remote:
                    if local[identity] != remote[identity]:
                        raise ValueError("An immutable action identity has conflicting payloads")
                    versions[identity] = local[identity]
                elif identity in local and identity[1] > incoming_coverage[identity[0]]:
                    versions[identity] = local[identity]
                elif identity in remote and identity[1] > self.coverage[identity[0]]:
                    versions[identity] = remote[identity]
            if versions:
                joined[record] = versions
        self.records = joined
        self.coverage = {device: max(self.coverage[device], incoming_coverage[device]) for device in DEVICES}
        pending = list(self.pending.values()) + checkpoint["pending"]
        self.pending = {}
        self.receive(pending)

    def values(self, record):
        return [action["value"] for _, action in sorted(self.records.get(record, {}).items())
                if action["kind"] == "put"]

    @property
    def pending_count(self):
        return len(self.pending)

    @property
    def deletion_count(self):
        return sum(action["kind"] == "delete" for versions in self.records.values() for action in versions.values())

    @property
    def conflict_count(self):
        return sum(len(versions) > 1 for versions in self.records.values())

    def check_invariants(self):
        validate_vector(self.coverage)
        for record, versions in self.records.items():
            if not versions:
                raise AssertionError("A retained record must contain at least one version")
            for identity, action in versions.items():
                validate_action(action)
                if not (identity == dot(action) and action["record"] == record
                        and action["sequence"] <= self.coverage[action["device"]]
                        and all(count <= self.coverage[device] for device, count in action["context"].items())
                        and all(other == identity or identity[1] > value["context"][identity[0]]
                                for other, value in versions.items())):
                    raise AssertionError("Record versions must be covered, causally maximal, and keyed consistently")
        for identity, action in self.pending.items():
            validate_action(action)
            if not (identity == dot(action) and identity[1] > self.coverage[identity[0]]):
                raise AssertionError("Pending actions must be keyed consistently and not covered")
        return True
