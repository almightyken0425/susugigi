"""Strictly reconcile the latest Monefy CSV with both import files.

``transactions.csv`` maps one-to-one to non-transfer rows. Each row in
``transfers.csv`` is expanded back into its ExpenseTransfer and
IncomeTransfer legs before the two complete data sets are compared.
"""

import csv
import sys
from collections import Counter
from datetime import datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import NamedTuple


SCRIPT_DIR = Path(__file__).resolve().parent
DATA_DIR = SCRIPT_DIR.parent / "original_db_data"
EXPORT_DIR = SCRIPT_DIR.parent / "export_data"
TRANSACTIONS_PATH = EXPORT_DIR / "transactions.csv"
TRANSFERS_PATH = EXPORT_DIR / "transfers.csv"

TRANSFER_CATEGORIES = {"ExpenseTransfer", "IncomeTransfer"}
RAW_HEADER_POSITIONS = {
    0: "date",
    1: "account",
    2: "category",
    3: "amount",
    4: "currency",
    5: "converted amount",
    6: "currency",
    7: "description",
}


class ReconciliationError(Exception):
    """Raised when an input file cannot be checked safely."""


class Record(NamedTuple):
    date: str
    account: str
    category: str
    amount: Decimal
    currency: str
    note: str


def latest_raw_csv() -> Path:
    candidates = list(DATA_DIR.glob("*.csv"))
    if not candidates:
        raise ReconciliationError(f"No raw CSV found in {DATA_DIR}")
    return max(candidates, key=lambda path: path.stat().st_mtime)


def normalize_date(value: str, location: str) -> str:
    value = value.strip()
    for date_format in ("%m/%d/%Y", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(value, date_format).date().isoformat()
        except ValueError:
            continue
    raise ReconciliationError(f"Invalid date at {location}: {value!r}")


def parse_amount(value: str, location: str) -> Decimal:
    try:
        amount = Decimal(value.replace(",", "").strip())
    except (InvalidOperation, AttributeError):
        raise ReconciliationError(
            f"Invalid amount at {location}: {value!r}"
        ) from None
    if not amount.is_finite():
        raise ReconciliationError(f"Non-finite amount at {location}: {value!r}")
    return amount


def require_headers(
    fieldnames: list[str] | None,
    required: tuple[str, ...],
    path: Path,
) -> None:
    if fieldnames is None:
        raise ReconciliationError(f"Missing header row in {path}")
    missing = [name for name in required if name not in fieldnames]
    if missing:
        raise ReconciliationError(
            f"Missing columns in {path}: {', '.join(missing)}"
        )


def value_at(row: dict[str, str | None], field: str, location: str) -> str:
    value = row.get(field)
    if value is None:
        raise ReconciliationError(f"Missing {field!r} at {location}")
    return value


def load_raw(path: Path) -> Counter[Record]:
    records: Counter[Record] = Counter()
    with path.open("r", encoding="utf-8-sig", newline="") as source:
        reader = csv.reader(source)
        try:
            header = next(reader)
        except StopIteration:
            raise ReconciliationError(f"Empty raw CSV: {path}") from None

        header_errors = [
            f"column {index + 1} must be {expected!r}"
            for index, expected in RAW_HEADER_POSITIONS.items()
            if len(header) <= index or header[index] != expected
        ]
        if header_errors:
            raise ReconciliationError(
                f"Unexpected raw CSV header in {path}: {'; '.join(header_errors)}"
            )

        for line_number, row in enumerate(reader, start=2):
            if not row:
                continue
            location = f"{path.name}:{line_number}"
            if len(row) != 8:
                raise ReconciliationError(
                    f"Expected 8 columns at {location}, got {len(row)}"
                )
            records[
                Record(
                    date=normalize_date(row[0], location),
                    account=row[1],
                    category=row[2],
                    amount=parse_amount(row[3], location),
                    currency=row[4],
                    note=row[7],
                )
            ] += 1
    return records


def load_transactions(path: Path) -> tuple[Counter[Record], int]:
    required = (
        "transaction_datetime",
        "category",
        "account",
        "amount",
        "currency",
        "note",
    )
    records: Counter[Record] = Counter()
    row_count = 0
    with path.open("r", encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        require_headers(reader.fieldnames, required, path)
        for line_number, row in enumerate(reader, start=2):
            location = f"{path.name}:{line_number}"
            if None in row:
                raise ReconciliationError(f"Unexpected extra column at {location}")
            category = value_at(row, "category", location)
            if category in TRANSFER_CATEGORIES:
                raise ReconciliationError(
                    f"Transfer category found in transactions file at {location}"
                )
            records[
                Record(
                    date=normalize_date(
                        value_at(row, "transaction_datetime", location), location
                    ),
                    account=value_at(row, "account", location),
                    category=category,
                    amount=parse_amount(value_at(row, "amount", location), location),
                    currency=value_at(row, "currency", location),
                    note=value_at(row, "note", location),
                )
            ] += 1
            row_count += 1
    return records, row_count


def load_transfers(path: Path) -> tuple[Counter[Record], int]:
    required = (
        "transfer_datetime",
        "from_account",
        "from_currency",
        "from_amount",
        "to_account",
        "to_currency",
        "to_amount",
        "note",
    )
    records: Counter[Record] = Counter()
    row_count = 0
    with path.open("r", encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        require_headers(reader.fieldnames, required, path)
        for line_number, row in enumerate(reader, start=2):
            location = f"{path.name}:{line_number}"
            if None in row:
                raise ReconciliationError(f"Unexpected extra column at {location}")
            date = normalize_date(
                value_at(row, "transfer_datetime", location), location
            )
            note = value_at(row, "note", location)
            from_amount = parse_amount(
                value_at(row, "from_amount", location), location
            )
            to_amount = parse_amount(value_at(row, "to_amount", location), location)

            records[
                Record(
                    date=date,
                    account=value_at(row, "from_account", location),
                    category="ExpenseTransfer",
                    amount=-from_amount.copy_abs(),
                    currency=value_at(row, "from_currency", location),
                    note=note,
                )
            ] += 1
            records[
                Record(
                    date=date,
                    account=value_at(row, "to_account", location),
                    category="IncomeTransfer",
                    amount=to_amount.copy_abs(),
                    currency=value_at(row, "to_currency", location),
                    note=note,
                )
            ] += 1
            row_count += 1
    return records, row_count


def format_record(record: Record) -> str:
    amount = format(record.amount, "f")
    return (
        f"{record.date} | {record.account} | {record.category} | "
        f"{amount} | {record.currency} | {record.note!r}"
    )


def report_differences(
    raw_records: Counter[Record],
    import_records: Counter[Record],
    limit: int = 20,
) -> int:
    missing = raw_records - import_records
    unexpected = import_records - raw_records
    difference_count = sum(missing.values()) + sum(unexpected.values())
    if difference_count == 0:
        print("PASS: Raw CSV and expanded import data are exactly equal.")
        return 0

    print(f"FAIL: {difference_count} differing record occurrence(s).")
    shown_groups = 0
    shown_occurrences = 0
    for label, differences in (
        ("Missing from import", missing),
        ("Unexpected in import", unexpected),
    ):
        if not differences or shown_groups >= limit:
            continue
        print(f"\n{label}:")
        for record, count in sorted(
            differences.items(), key=lambda item: tuple(map(str, item[0]))
        ):
            print(f"  {count} x {format_record(record)}")
            shown_groups += 1
            shown_occurrences += count
            if shown_groups >= limit:
                break
    if difference_count > shown_occurrences:
        print(
            f"\n... {difference_count - shown_occurrences} more "
            "occurrence(s) not shown"
        )
    return 1


def main() -> int:
    try:
        raw_path = latest_raw_csv()
        for required_path in (TRANSACTIONS_PATH, TRANSFERS_PATH):
            if not required_path.is_file():
                raise ReconciliationError(f"Missing import file: {required_path}")

        raw_records = load_raw(raw_path)
        transaction_records, transaction_count = load_transactions(TRANSACTIONS_PATH)
        transfer_records, transfer_count = load_transfers(TRANSFERS_PATH)
        import_records = transaction_records + transfer_records

        print("Monefy import reconciliation")
        print(f"Raw CSV: {raw_path.name}")
        print(f"Raw records: {sum(raw_records.values())}")
        print(f"Transactions: {transaction_count}")
        print(f"Transfers: {transfer_count} ({transfer_count * 2} expanded legs)")
        print(f"Expanded import records: {sum(import_records.values())}")
        return report_differences(raw_records, import_records)
    except (OSError, csv.Error, ReconciliationError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
