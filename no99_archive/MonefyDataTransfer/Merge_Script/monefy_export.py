"""
Monefy Database Export Script
==============================
從 Monefy 的 SQLite 資料庫匯出資料到 CSV 格式 (混合模式)

1. Transactions (一般交易): 從原始 CSV 匯出檔 (monefy-2026-01-21_12-26-22.csv) 讀取
   - 原因: 原始 CSV 包含所有已實現的交易，且金額已經過確認。
   - 過濾: 排除 'ExpenseTransfer' 和 'IncomeTransfer' (避免與 DB 轉帳重複)

2. Transfers (轉帳): 從 SQLite 資料庫 讀取
   - 原因: DB 包含精確的 currency_id 和 exchange_rate 資訊。

輸出檔案:
- transactions.csv: 交易記錄 (來源: Raw CSV)
- transfers.csv: 轉帳記錄 (來源: DB)
"""

import sqlite3
import csv
from datetime import datetime, timedelta
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from pathlib import Path
import sys
import calendar

# 設定路徑
SCRIPT_DIR = Path(__file__).parent
DATA_DIR = SCRIPT_DIR / "../Original_DB_Data"
STORAGE_QUANTUM = Decimal("0.0001")


def parse_source_amount(amount_str: str) -> Decimal:
    """Parse an exact source amount and reject precision SuSuGiGi cannot store."""
    try:
        amount = Decimal(amount_str.replace(',', ''))
    except (InvalidOperation, AttributeError) as exc:
        raise ValueError(f"Invalid source amount: {amount_str}") from exc

    if amount != amount.quantize(STORAGE_QUANTUM):
        raise ValueError(f"Source amount exceeds 4 decimal places: {amount_str}")
    return amount


def format_storage_amount(amount) -> str:
    """Format with SuSuGiGi's 4-decimal storage precision without trailing zeros."""
    value = amount if isinstance(amount, Decimal) else Decimal(str(amount))
    value = value.quantize(STORAGE_QUANTUM, rounding=ROUND_HALF_UP)
    text = format(value, 'f')
    return text.rstrip('0').rstrip('.') if '.' in text else text

def get_latest_file(directory: Path, pattern: str) -> Path | None:
    files = list(directory.glob(pattern))
    if not files:
        return None
    return max(files, key=lambda f: f.stat().st_mtime)

DEFAULT_DB_PATH = get_latest_file(DATA_DIR, "*.db")
RAW_CSV_PATH = get_latest_file(DATA_DIR, "*.csv")

if DEFAULT_DB_PATH is None:
    print(f"Error: No .db file found in {DATA_DIR}")
    sys.exit(1)
if RAW_CSV_PATH is None:
    print(f"Error: No .csv file found in {DATA_DIR}")
    sys.exit(1)


def ticks_to_datetime(ticks: int) -> datetime | None:
    """轉換 .NET Ticks 到 Python datetime"""
    if ticks is None:
        return None
    try:
        base = datetime(1, 1, 1)
        delta = timedelta(microseconds=ticks/10)
        return base + delta
    except (OSError, OverflowError, ValueError):
        return None


def cents_to_decimal(cents: int, currency_code: str = None, is_schedule: bool = False) -> float:
    """轉換 cents 到 decimal 格式"""
    return cents / 1000.0


def normalize_date(date_str: str) -> str:
    """標準化日期為 YYYY-MM-DD（吃 'YYYY-MM-DD HH:MM:SS' 或 'M/D/YYYY'）"""
    if not date_str:
        return ""
    try:
        if '-' in date_str:
            return date_str.split()[0]
        if '/' in date_str:
            return datetime.strptime(date_str, '%m/%d/%Y').strftime('%Y-%m-%d')
    except ValueError:
        pass
    return date_str


def build_raw_transfer_pool(raw_csv_path: Path) -> list:
    """從 raw CSV 載入 ExpenseTransfer / IncomeTransfer 兩腳的『實際金額庫』供 Smart Match。"""
    pool = []
    with open(raw_csv_path, 'r', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        for row in reader:
            cat = row.get('category', '')
            if cat in ('ExpenseTransfer', 'IncomeTransfer'):
                try:
                    amount = parse_source_amount(row['amount'])
                except (ValueError, KeyError):
                    amount = Decimal('0')
                pool.append({
                    'date': normalize_date(row.get('date', '')),
                    'account': row.get('account', ''),
                    'category': cat,
                    'amount': amount,
                    'used': False,
                })
    return pool


def match_actual_amount(pool: list, date: str, account: str, category: str, approx_amount: float):
    """在 pool 中找 (date, account, category) 吻合且未用過、金額最接近 approx 的一筆，回傳其實際金額。

    用 DB 估算值當搜尋鍵：估算與實際只差匯率捨入，當天同帳戶的候選中取最接近的即為正解。
    沿用 merge_for_reconciliation.py 驗證過、可達 zero-discrepancy 的配對策略。
    """
    target_date = normalize_date(date)
    approx = approx_amount if isinstance(approx_amount, Decimal) else Decimal(str(approx_amount))
    best_idx, min_diff = -1, Decimal('Infinity')
    for i, r in enumerate(pool):
        if (not r['used'] and r['date'] == target_date
                and r['account'] == account and r['category'] == category):
            diff = abs(r['amount'] - approx)
            if diff < min_diff:
                min_diff, best_idx = diff, i
    if best_idx != -1:
        pool[best_idx]['used'] = True
        return pool[best_idx]['amount']
    return None


def get_exchange_rate(cursor, from_currency_id: int, to_currency_id: int, 
                      transfer_ticks: int) -> tuple[float, bool, str]:
    """查詢最接近轉帳日期的匯率"""
    if from_currency_id == to_currency_id:
        return 1.0, False, 'SameCurrency'
    
    # 1. 嘗試正向完全匹配
    cursor.execute('''
        SELECT RateCents 
        FROM "CurrencyRate" 
        WHERE CurrencyFromId = ? AND CurrencyToId = ?
        AND RateDate = ?
        AND DeletedOn IS NULL
        LIMIT 1
    ''', (from_currency_id, to_currency_id, transfer_ticks))
    
    result = cursor.fetchone()
    if result:
        rate = result[0] / 1000000
        return rate, False, 'Exact'

    # 2. 嘗試反向完全匹配
    cursor.execute('''
        SELECT RateCents 
        FROM "CurrencyRate" 
        WHERE CurrencyFromId = ? AND CurrencyToId = ?
        AND RateDate = ?
        AND DeletedOn IS NULL
        LIMIT 1
    ''', (to_currency_id, from_currency_id, transfer_ticks))
    
    result = cursor.fetchone()
    if result:
        rate = result[0] / 1000000
        return 1 / rate if rate != 0 else 0, True, 'Exact'

    # 3. 嘗試正向最近查詢
    cursor.execute('''
        SELECT RateCents, RateDate 
        FROM "CurrencyRate" 
        WHERE CurrencyFromId = ? AND CurrencyToId = ?
        AND DeletedOn IS NULL
        ORDER BY ABS(RateDate - ?)
        LIMIT 1
    ''', (from_currency_id, to_currency_id, transfer_ticks))
    
    result = cursor.fetchone()
    if result:
        rate = result[0] / 1000000
        return rate, False, 'Nearest'
    
    # 4. 嘗試反向最近查詢
    cursor.execute('''
        SELECT RateCents, RateDate 
        FROM "CurrencyRate" 
        WHERE CurrencyFromId = ? AND CurrencyToId = ?
        AND DeletedOn IS NULL
        ORDER BY ABS(RateDate - ?)
        LIMIT 1
    ''', (to_currency_id, from_currency_id, transfer_ticks))
    
    result = cursor.fetchone()
    if result:
        rate = result[0] / 1000000
        return 1 / rate if rate != 0 else 0, True, 'Nearest'
    
    return 0.0, False, 'NotFound'


def export_transactions_from_csv(csv_path: Path, output_path: Path) -> int:
    """
    從 Raw CSV 匯出交易記錄到 transactions.csv
    
    邏輯:
    1. 讀取 Raw CSV
    2. 排除 category 為 'ExpenseTransfer' 或 'IncomeTransfer' 的記錄 (由 DB export_transfers 處理)
    3. 轉換格式寫入 transactions.csv
    """
    if not csv_path.exists():
        print(f"錯誤: 找不到 Raw CSV 檔案 {csv_path}")
        return 0

    print(f"Reading Raw CSV from: {csv_path.name}")
    
    transactions = []
    
    with open(csv_path, 'r', encoding='utf-8-sig') as f:
        reader = csv.reader(f)
        headers = next(reader)  # Skip header row
        # Raw CSV headers: date,account,category,amount,currency,converted amount,currency,description
        # 注意：有兩個 "currency" 欄位，第一個是原始幣別(index 4)，第二個是轉換後幣別(index 6)
        # 我們要讀取的是第一個 currency (原始幣別)
        
        for row in reader:
            if len(row) < 8:
                continue
                
            date_str = row[0]
            account = row[1]
            category = row[2]
            amount_str = row[3]
            original_currency = row[4]  # 原始幣別
            # row[5] = converted amount
            # row[6] = converted currency (通常是 TWD)
            description = row[7] if len(row) > 7 else ''
            
            # [Filter] Exclude Transfers (Handled by DB export)
            if category in ('ExpenseTransfer', 'IncomeTransfer'):
                continue
                
            # Parse Date
            # Format: 12/31/2015 or 6/10/2016
            try:
                dt_obj = datetime.strptime(date_str, '%m/%d/%Y')
                # CSV dates are usually just dates, so time is 00:00:00
                datetime_str = dt_obj.strftime('%Y-%m-%d %H:%M:%S')
            except ValueError:
                # Try handling other potential formats provided by system locale?
                # For now stick to strict m/d/Y as seen in the file
                print(f"Warning: Could not parse date {date_str}, skipping.")
                continue

            # Parse Amount
            try:
                # Remove commas if any (e.g. "1,000.00")
                amount = parse_source_amount(amount_str)
            except ValueError:
                 print(f"Warning: Could not parse amount {amount_str}, skipping.")
                 continue

            transactions.append({
                'datetime_str': datetime_str,
                'category': category,
                'account': account,
                'amount': amount,
                'currency': original_currency,  # 使用原始幣別
                'note': description,
                'is_virtual': False, # Raw CSV is always realized
                'is_ignored': False
            })
            
    # Sort by date
    transactions.sort(key=lambda x: x['datetime_str'])
    
    # Write to output
    with open(output_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow([
            'transaction_datetime', 'category', 'account', 
            'amount', 'currency', 'note', 'is_virtual', 'is_ignored'
        ])
        
        for tx in transactions:
            writer.writerow([
                tx['datetime_str'],
                tx['category'],
                tx['account'],
                format_storage_amount(tx['amount']),
                tx['currency'],
                tx['note'],
                tx['is_virtual'],
                tx['is_ignored']
            ])
            
    return len(transactions)


def export_transfers(cursor, output_path: Path, raw_csv_path: Path) -> int:
    """
    匯出轉帳記錄到 transfers.csv（pairing 來自 DB；金額用 raw CSV 實際值經 Smart Match 修正）

    DB 的 Transfer 表只存 AmountCents（轉出側），轉入金額過去用匯率估算、與 Monefy 實際值有捨入差。
    改成用 DB 估算值當搜尋鍵，去 raw CSV 的 ExpenseTransfer / IncomeTransfer 撈實際金額，
    讓 transfers.csv（匯入來源）與 Monefy 完全一致。
    """
    query = '''
        SELECT 
            tr.CreatedOn,
            af.Name as FromAccountName,
            cf.AlphabeticCode as FromCurrencyCode,
            cf.Id as FromCurrencyId,
            at.Name as ToAccountName,
            ct.AlphabeticCode as ToCurrencyCode,
            ct.Id as ToCurrencyId,
            tr.AmountCents,
            tr.Note
        FROM "Transfer" tr
        JOIN "Account" af ON tr.AccountFromId = af.Id
        JOIN "Account" at ON tr.AccountToId = at.Id
        JOIN "Currency" cf ON af.CurrencyId = cf.Id
        JOIN "Currency" ct ON at.CurrencyId = ct.Id
        WHERE tr.DeletedOn IS NULL
          AND af.DeletedOn IS NULL
          AND at.DeletedOn IS NULL
        ORDER BY tr.CreatedOn
    '''
    
    cursor.execute(query)
    rows = cursor.fetchall()

    # raw CSV 兩腳實際金額庫（供 Smart Match）。期望大小 = 2 × 轉帳數。
    pool = build_raw_transfer_pool(raw_csv_path)
    matched_legs = 0

    count = 0
    with open(output_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow([
            'transfer_datetime', 'from_account', 'from_currency', 'from_amount',
            'to_account', 'to_currency', 'to_amount', 'exchange_rate', 'rate_type', 'note'
        ])

        for row in rows:
            (created_on, from_account, from_currency_code, from_currency_id,
             to_account, to_currency_code, to_currency_id, amount_cents, note) = row

            # 轉換時間
            dt = ticks_to_datetime(created_on)
            if dt is None:
                continue
            datetime_str = dt.strftime('%Y-%m-%d %H:%M:%S')

            # DB 估算值：from = AmountCents；to = from × 匯率（僅作為 Smart Match 的搜尋鍵）
            from_est = cents_to_decimal(amount_cents, from_currency_code, is_schedule=False)
            if from_currency_id == to_currency_id:
                rate_type = 'SameCurrency'
                to_est = from_est
            else:
                _rate, _, rate_type = get_exchange_rate(
                    cursor, from_currency_id, to_currency_id, created_on
                )
                to_est = from_est * _rate if _rate else 0.0

            # Smart Match：用估算值撈 raw CSV 的實際金額，DB 只負責配對(誰轉誰)
            m_from = match_actual_amount(pool, datetime_str, from_account, 'ExpenseTransfer', -abs(from_est))
            m_to = match_actual_amount(pool, datetime_str, to_account, 'IncomeTransfer', abs(to_est))
            from_amount = abs(m_from) if m_from is not None else Decimal(str(from_est))
            to_amount = abs(m_to) if m_to is not None else Decimal(str(to_est))
            matched_legs += (m_from is not None) + (m_to is not None)
            if m_from is not None and m_to is not None:
                source = 'RawCSV'
            elif m_from is not None or m_to is not None:
                # Cross-currency transfer matched on only one leg → the other leg's amount is a
                # DB estimate, so don't claim full RawCSV fidelity. Mark Partial for honesty.
                source = 'Partial'
            else:
                source = rate_type

            # exchange_rate 欄改記實際 to/from（資訊用；匯入忽略此欄）
            exchange_rate = (to_amount / from_amount) if from_amount else 0.0

            writer.writerow([
                datetime_str,
                from_account or '',
                from_currency_code or '',
                format_storage_amount(from_amount),
                to_account or '',
                to_currency_code or '',
                format_storage_amount(to_amount),
                f'{exchange_rate:.5f}',
                source,
                note or ''
            ])
            count += 1

    print(f"   Smart Match：{matched_legs}/{count * 2} 腳用 raw CSV 實際金額；pool 剩 {sum(1 for r in pool if not r['used'])} 筆未用")
    return count


def main(db_path: Path = None):
    """主程式進入點"""
    if db_path is None:
        db_path = DEFAULT_DB_PATH
    
    if not db_path.exists():
        print(f"錯誤: 找不到資料庫檔案 {db_path}")
        sys.exit(1)
    
    print("=" * 60)
    print("Monefy Hybrid Export Script")
    print("=" * 60)
    print(f"DB Path: {db_path}")
    print(f"Raw CSV Path: {RAW_CSV_PATH}")
    
    # 連接資料庫 (for Transfers)
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    try:
        # 1. 匯出 Transactions (From Raw CSV)
        transactions_path = SCRIPT_DIR / "../Export_Data/transactions.csv"
        print(f"\n[1/2] 匯出交易記錄 (來源: Raw CSV)...")
        tx_count = export_transactions_from_csv(RAW_CSV_PATH, transactions_path)
        print(f"✓ 已匯出 {tx_count} 筆交易到 {transactions_path.name}")
        
        # 2. 匯出 Transfers (From DB)
        transfers_path = SCRIPT_DIR / "../Export_Data/transfers.csv"
        print(f"\n[2/2] 匯出轉帳記錄 (來源: DB)...")
        tr_count = export_transfers(cursor, transfers_path, RAW_CSV_PATH)
        print(f"✓ 已匯出 {tr_count} 筆轉帳到 {transfers_path.name}")
        
        print("\n" + "=" * 60)
        print("匯出完成!")
        print("=" * 60)
        
    finally:
        conn.close()


if __name__ == "__main__":
    # 支援命令列參數指定資料庫路徑
    if len(sys.argv) > 1:
        db_path = Path(sys.argv[1])
    else:
        db_path = None
    
    main(db_path)
