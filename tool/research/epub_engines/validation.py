def certify(rows, references, reference_digest):
    certified = []
    for raw in rows:
        row = dict(raw)
        row["content_verified"] = False
        key = "/".join(str(row.get(field, "")) for field in ("engine", "book", "case"))
        reference = references.get(key)
        failure = None
        if reference is None:
            failure = "No independently checked reference for this case"
        elif reference.get("run_id") == row.get("run_id"):
            failure = "A capture cannot be its own independent reference"
        elif not all(reference.get(field) is True for field in ("source_validated", "ocr_validated", "image_reviewed")):
            failure = "Reference source, rendered text, or image review is incomplete"
        elif row.get("reference_manifest_sha256") != reference_digest:
            failure = "Device and host used different reference manifests"
        elif any(row.get(field) != reference.get(field) for field in
                 ("capture_sha256", "location", "location_format", "text_size_css_px", "book_sha256")):
            failure = "Window pixels, destination, settings, or corpus differ from the reference"
        elif " ".join(row.get("visible_text", "").split()) != " ".join(reference.get("visible_text", "").split()):
            failure = "Visible text differs from the independently checked destination"
        elif row.get("pixel_copy_code") != 0:
            failure = "Window copy failed"
        if failure:
            row["validation_error"] = failure
            row["error"] = row.get("error") or failure
        else:
            row["content_verified"] = True
            row["reference_run_id"] = reference["run_id"]
            row["reference_manifest_sha256"] = reference_digest
            row["reference_sha256"] = reference["capture_sha256"]
            row["expected"] = f'{reference["location"]}@{reference["text_size_css_px"]}'
            row["actual"] = f'{row["location"]}@{row["text_size_css_px"]}'
            row["text"] = row["visible_text"]
        certified.append(row)
    return certified
