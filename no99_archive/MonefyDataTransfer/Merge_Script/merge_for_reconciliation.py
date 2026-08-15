"""
合併 transactions.csv 與 transfers.csv 為 reconciliation.csv
用於 Google Sheet 資料透視表對帳

輸出格式：
- datetime: 交易時間
- account: 帳戶名稱
- category: 類別名稱，轉帳會顯示為「轉出」或「轉入」
- amount: 金額，正數為收入，負數為支出
- currency: 幣別
- note: 備註
"""

import csv
from datetime import datetime
from pathlib import Path

# 檔案路徑
SCRIPT_DIR = Path(__file__).parent
TRANSACTIONS_PATH = SCRIPT_DIR / "../Export_Data/transactions.csv"
TRANSFERS_PATH = SCRIPT_DIR / "../Export_Data/transfers.csv"
OUTPUT_PATH = SCRIPT_DIR / "../Export_Data/reconciliation.csv"
COMPARISON_OUTPUT_PATH = SCRIPT_DIR / "../Export_Data/monefy_raw_comparison.csv"

DATA_DIR = SCRIPT_DIR / "../Original_DB_Data"
files = list(DATA_DIR.glob("*.csv"))
if not files:
    print(f"Error: No .csv file found in {DATA_DIR}")
    exit(1)
RAW_CSV_PATH = max(files, key=lambda f: f.stat().st_mtime)

def normalize_date(date_str):
    """
    Standardize date string to YYYY-MM-DD
    Handles:
    - 2026-01-21 12:34:56 -> 2026-01-21
    - 1/21/2026 -> 2026-01-21
    """
    if not date_str:
        return ""
    try:
        # Check if already YYYY-MM-DD (possibly with time)
        if '-' in date_str:
            return date_str.split()[0]
        # Check if M/D/YYYY
        elif '/' in date_str:
            return datetime.strptime(date_str, '%m/%d/%Y').strftime('%Y-%m-%d')
    except ValueError:
        pass
    return date_str

def main():
    print("=== 開始合併與對帳程序 ===")
    
    # --- 步驟 0: 載入 Raw CSV 的轉帳資料建立「正確金額庫」 ---
    # 原因: DB 儲存的轉帳金額可能有浮點數誤差 (如 100000.004)，但 Raw CSV 是 100000.0
    # 為了達成 Zero Discrepancy，我們必須優先使用 Raw CSV 的數值。
    print(f"載入 Raw CSV 建立轉帳金額匹配庫: {RAW_CSV_PATH.name}")
    raw_transfer_pool = [] 
    
    with open(RAW_CSV_PATH, 'r', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        for row in reader:
            cat = row['category']
            if cat in ['ExpenseTransfer', 'IncomeTransfer']:
                try:
                    amount = float(row['amount'].replace(',', ''))
                except ValueError:
                    amount = 0.0
                    
                raw_transfer_pool.append({
                    'date': normalize_date(row['date']),
                    'account': row['account'],
                    'category': cat,
                    'amount': amount,
                    'note': row['description'],
                    'used': False # 標記是否已被匹配
                })
    print(f"  共載入 {len(raw_transfer_pool)} 筆 Raw Transfer 資料")

    def get_matched_amount(date, account, category, approx_amount):
        """
        在 Raw CSV pool 中尋找符合的轉帳紀錄，並回傳其精確金額。
        策略：
        1. 篩選出 Date, Account, Category 完全吻合且尚未使用的候選紀錄。
        2. 從候選紀錄中找出與 approx_amount 差距最小的一筆。
        3. 即使差距很大 (匯率差)，只要是當天最接近的，就視為匹配。
        """
        target_date = normalize_date(date)
        
        # 尋找候選人 (Date, Account, Category 必須吻合)
        candidates = []
        for i, r in enumerate(raw_transfer_pool):
            if (not r['used'] and 
                r['date'] == target_date and 
                r['account'] == account and 
                r['category'] == category):
                candidates.append((i, r))
        
        # 從候選人中找金額最接近的
        best_idx = -1
        min_diff = float('inf')
        
        for i, r in candidates:
            diff = abs(r['amount'] - approx_amount)
            if diff < min_diff:
                min_diff = diff
                best_idx = i
        
        if best_idx != -1:
            raw_transfer_pool[best_idx]['used'] = True
            # print(f"  [Match] DB: {approx_amount} -> Raw: {raw_transfer_pool[best_idx]['amount']} (Diff: {min_diff})")
            return raw_transfer_pool[best_idx]['amount']
        
        return None # 真的沒紀錄才 fallback (理論上不應發生)

    # ------------------------------------------------------------------

    all_records = []
    comparison_records = []
    
    # 步驟 1: 讀取 transactions.csv (已過濾掉轉帳)
    print("讀取 transactions.csv...")
    with open(TRANSACTIONS_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Pivot Summary Data
            all_records.append({
                'datetime': row['transaction_datetime'],
                'account': row['account'],
                'category': row['category'],
                'amount': float(row['amount']),
                'currency': row['currency'],
                'note': row['note'],
                'record_type': 'transaction'
            })
            
            # Raw Comparison Data (Mirroring Raw CSV structure)
            comparison_records.append({
                'datetime': row['transaction_datetime'],
                'account': row['account'],
                'category': row['category'],
                'amount': float(row['amount']),
                'currency': row['currency'],
                'note': row['note']
            })
            
    print(f"  讀取 {len(all_records)} 筆交易")
    
    # 步驟 2: 讀取 transfers.csv 並展開 (Transactions from DB)
    print("讀取 transfers.csv 並進行 Smart Match...")
    transfer_count = 0
    match_count = 0
    
    with open(TRANSFERS_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            transfer_count += 1
            
            # --- 處理轉出 (From) ---
            # DB 原始值
            db_from_amount = -abs(float(row['from_amount']))
            # Smart Match
            matched_from_amt = get_matched_amount(
                row['transfer_datetime'],
                row['from_account'],
                'ExpenseTransfer',
                db_from_amount
            )
            final_from_amt = matched_from_amt if matched_from_amt is not None else db_from_amount
            if matched_from_amt is not None: match_count += 1

            # --- 處理轉入 (To) ---
            # DB 原始值
            db_to_amount = abs(float(row['to_amount']))
            # Smart Match
            matched_to_amt = get_matched_amount(
                row['transfer_datetime'],
                row['to_account'],
                'IncomeTransfer',
                db_to_amount
            )
            final_to_amt = matched_to_amt if matched_to_amt is not None else db_to_amount
            if matched_to_amt is not None: match_count += 1
            
            # 建立紀錄 - Reconciliation
            all_records.append({
                'datetime': row['transfer_datetime'],
                'account': row['from_account'],
                'category': f"轉出至 {row['to_account']}",
                'amount': final_from_amt,
                'currency': row['from_currency'],
                'note': row['note'],
                'record_type': 'transfer'
            })
            all_records.append({
                'datetime': row['transfer_datetime'],
                'account': row['to_account'],
                'category': f"轉入自 {row['from_account']}",
                'amount': final_to_amt,
                'currency': row['to_currency'],
                'note': row['note'],
                'record_type': 'transfer'
            })
            
            # 建立紀錄 - Raw Comparison
            comparison_records.append({
                'datetime': row['transfer_datetime'],
                'account': row['from_account'],
                'category': 'ExpenseTransfer',
                'amount': final_from_amt,
                'currency': row['from_currency'],
                'note': row['note']
            })
            comparison_records.append({
                'datetime': row['transfer_datetime'],
                'account': row['to_account'],
                'category': 'IncomeTransfer',
                'amount': final_to_amt,
                'currency': row['to_currency'],
                'note': row['note']
            })
            
    print(f"  讀取 {transfer_count} 筆轉帳，展開為 {transfer_count * 2} 筆紀錄")
    print(f"  Smart Match 成功匹配並修正了 {match_count} 個轉帳金額 (包含轉出與轉入 leg)")
    
    # 3. 排序與輸出
    all_records.sort(key=lambda x: x['datetime'])
    comparison_records.sort(key=lambda x: x['datetime'])
    
    # 輸出合併檔案 (reconciliation.csv)
    print(f"輸出至 {OUTPUT_PATH}...")
    with open(OUTPUT_PATH, 'w', encoding='utf-8-sig', newline='') as f:
        fieldnames = ['datetime', 'account', 'category', 'amount', 'currency', 'note', 'record_type']
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(all_records)
    print(f"  完成 reconciliation.csv! 共 {len(all_records)} 筆紀錄")
    
    # 輸出對照檔案 (monefy_raw_comparison.csv)
    print(f"輸出對照檔案至 {COMPARISON_OUTPUT_PATH}...")
    with open(COMPARISON_OUTPUT_PATH, 'w', encoding='utf-8-sig', newline='') as f:
        fieldnames = ['datetime', 'account', 'category', 'amount', 'currency', 'note']
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(comparison_records)
    print(f"  完成 monefy_raw_comparison.csv! 共 {len(comparison_records)} 筆紀錄")
    
    # 統計各帳戶摘要
    print("\n=== 帳戶摘要 (reconciliation.csv) ===")
    account_summary = {}
    for record in all_records:
        acc = record['account']
        if acc not in account_summary:
            account_summary[acc] = {'count': 0, 'total': 0.0}
        account_summary[acc]['count'] += 1
        account_summary[acc]['total'] += record['amount']
    
    for acc in sorted(account_summary.keys()):
        info = account_summary[acc]
        print(f"  {acc}: {info['count']} 筆, 淨額 {info['total']:,.2f}")

if __name__ == '__main__':
    main()
