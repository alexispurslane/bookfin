"""Conservative page-local screen for the bounded host proof, not fidelity validation.

Source blocks and their character anchors remain unchanged. A candidate passes
only these geometry checks; missing letters and semantic order need independent
source comparison. No decision joins text across a source-page boundary.
"""

from statistics import median


def _paragraphs(blocks):
    rows = {}
    for block in sorted(blocks, key=lambda block: (-block["baseline"], block["x"])):
        rows.setdefault(block["baseline"], []).append(block)
    baselines = list(rows)
    gaps = [first - second for first, second in zip(baselines, baselines[1:])]
    line_spacing = median(gaps) if gaps else 0
    paragraphs = []
    previous = None
    for baseline, row in rows.items():
        first = row[0]
        heading = any(block["heading"] for block in row)
        text = " ".join(block["text"] for block in row)
        continues = (
            previous is not None and not heading and not paragraphs[-1]["heading"]
            and 0 < previous["baseline"] - baseline <= min(line_spacing * 1.4, 36)
            and abs(previous["x"] - first["x"]) <= 12
            and max(previous["size"], first["size"]) <= min(previous["size"], first["size"]) * 1.15
        )
        if continues:
            paragraphs[-1]["text"] += " " + text
            paragraphs[-1]["source_blocks"].extend(row)
        else:
            paragraphs.append({"page": first["page"], "heading": heading,
                               "text": text, "source_blocks": list(row)})
        previous = first
    return paragraphs


def assess_page(blocks, *, source_layer_errors=()):
    """Choose candidate text or original-page fallback with separate causes.

    source_layer_errors contains independently observed source-layer defects,
    not defects inferred from geometry. Callers must bind that evidence to the
    exact source bytes and page. Empty evidence means unchecked, not correct.
    """
    if len({block["page"] for block in blocks}) > 1:
        raise ValueError("Assess one source page at a time")
    rows = {}
    for block in blocks:
        rows.setdefault(block["baseline"], []).append(block)
    mixed_blocks = sum(
        any(abs(second - first) > 5 for first, second in zip(block["source_indices"], block["source_indices"][1:]))
        for block in blocks
    )
    short_blocks = sum(len(block["text"].split()) <= 2 for block in blocks)
    split_rows = sum(len(row) > 1 for row in rows.values())
    parallel_rows = 0
    for row in rows.values():
        ordered = sorted(row, key=lambda block: block["x"])
        if any(abs(second["source_indices"][0] - first["source_indices"][-1]) > 5
               for first, second in zip(ordered, ordered[1:])):
            parallel_rows += 1
    reasons = []
    if mixed_blocks:
        reasons.append("discontinuous-source-order")
    if parallel_rows >= 3:
        reasons.append("parallel-text-groups")
    if len(blocks) >= 4 and short_blocks / len(blocks) >= 0.8:
        reasons.append("fragmented-text")
    if source_layer_errors:
        reasons.append("observed-source-layer-errors")
    status = "absent" if not blocks else "unreliable" if reasons else "candidate"
    return {
        "status": status,
        "view": "reflow" if status == "candidate" else "original-page",
        "reasons": reasons,
        "source_layer": "observed-errors" if source_layer_errors else "unchecked",
        "source_layer_errors": list(source_layer_errors),
        "future_ocr_reason": "absent-text" if not blocks else "observed-source-layer-errors" if source_layer_errors else None,
        "paragraphs": _paragraphs(blocks) if status == "candidate" else [],
        "metrics": {"blocks": len(blocks), "mixed_blocks": mixed_blocks,
                    "split_rows": split_rows, "parallel_rows": parallel_rows,
                    "short_blocks": short_blocks},
    }
