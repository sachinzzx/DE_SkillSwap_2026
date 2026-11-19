#!/usr/bin/env python3
"""
Optimized Benchmark Consistency & Validation Validator (CP3)
Team: T0103 (SkillSwap) · Section: A · Database: PostgreSQL 18
"""

import csv
import os
import re
import sys

def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    summary_path = os.path.join(root, "benchmarks", "results", "optimized", "summary.csv")
    results_dir = os.path.join(root, "benchmarks", "results", "optimized")
    report_path = os.path.join(root, "docs", "04_optimization_report.md")

    print("=== Validating CP3 Optimized Benchmark Artifacts ===")

    # 1. Verify summary.csv
    if not os.path.exists(summary_path):
        print(f"FAIL: {summary_path} not found.")
        sys.exit(1)

    with open(summary_path, mode="r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        csv_rows = {row["query_id"]: row for row in reader}

    if len(csv_rows) != 30:
        print(f"FAIL: Expected 30 queries in optimized summary.csv, found {len(csv_rows)}.")
        sys.exit(1)
    print(f"[✓] optimized summary.csv verified: exactly {len(csv_rows)} queries found.")

    # 2. Verify all raw plan files
    plan_data = {}
    for qid in sorted(csv_rows.keys()):
        raw_plan = os.path.join(results_dir, f"{qid}.txt")
        if not os.path.exists(raw_plan):
            print(f"FAIL: Raw plan file {raw_plan} missing.")
            sys.exit(1)

        with open(raw_plan, mode="r", encoding="utf-8") as f:
            content = f.read()

        runs = re.findall(r"=== " + qid + r" run (\d+) ===[\s\S]*?Execution Time: ([0-9.]+)", content)
        if len(runs) != 3:
            print(f"FAIL: {qid} has {len(runs)} execution runs, expected 3.")
            sys.exit(1)

        times = [float(r[1]) for r in runs]
        calc_avg = sum(times) / 3.0
        plan_data[qid] = (times, calc_avg)

        # Cross check with summary.csv
        csv_avg = float(csv_rows[qid]["avg_ms"])
        if abs(calc_avg - csv_avg) > 0.002:
            print(f"FAIL: Average mismatch for {qid}: calculated {calc_avg:.3f}, csv has {csv_avg:.3f}.")
            sys.exit(1)

    print("[✓] All 30 raw plan files verified (3 runs each, exact arithmetic mean match).")

    # 3. Verify Markdown report
    if not os.path.exists(report_path):
        print(f"FAIL: {report_path} not found.")
        sys.exit(1)

    with open(report_path, mode="r", encoding="utf-8") as f:
        md_content = f.read()

    md_matches = re.findall(
        r"\|\s*\*\*([RW][0-9]+)\*\*\s*\|\s*([0-9.]+)\s*\|[^|]*\|[^|]*\|\s*\*\*([0-9.]+)\*\*\s*\|",
        md_content
    )

    if len(md_matches) != 30:
        print(f"FAIL: Markdown table contains {len(md_matches)} queries, expected 30.")
        sys.exit(1)

    for qid, base_avg, opt_avg in md_matches:
        times, exp_avg = plan_data[qid]
        if abs(float(opt_avg) - exp_avg) > 0.002:
            print(f"FAIL: Average mismatch in markdown report for {qid}: got {opt_avg}, expected {exp_avg:.3f}.")
            sys.exit(1)

    print("[✓] Markdown report docs/04_optimization_report.md verified: exact match with plans and summary.csv.")
    print("=== All CP3 deliverables verified 100% consistent and accurate ===")

if __name__ == "__main__":
    main()
