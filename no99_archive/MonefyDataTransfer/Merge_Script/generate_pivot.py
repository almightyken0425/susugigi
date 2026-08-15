import pandas as pd
from pathlib import Path
import sys

# 設定路徑
SCRIPT_DIR = Path(__file__).parent
INPUT_FILE = SCRIPT_DIR / "../Export_Data/reconciliation.csv"
OUTPUT_FILE = SCRIPT_DIR / "../Export_Data/pivot_summary.csv"

def main():
    # 檢查輸入檔案是否存在
    if not INPUT_FILE.exists():
        print(f"錯誤: 找不到輸入檔案 {INPUT_FILE}")
        return

    print(f"正在讀取: {INPUT_FILE}")
    try:
        df = pd.read_csv(INPUT_FILE)
    except Exception as e:
        print(f"讀取 CSV 失敗: {e}")
        return

    # 轉為小寫比較保險 (reconciliation.csv headers are lowercase)
    df.columns = [c.lower() for c in df.columns]

    # 檢查必要欄位
    required_columns = {'account', 'category', 'amount'}
    if not required_columns.issubset(df.columns):
        print(f"錯誤: CSV 缺少必要欄位. 需要: {required_columns}, 實際: {df.columns.tolist()}")
        return

    print("正在生成透視表 (account -> category)...")
    
    # 確保金額為數字
    df['amount'] = pd.to_numeric(df['amount'], errors='coerce').fillna(0)

    # 群組加總
    # 按照 account, category, record_type 分群，計算 amount 總和
    pivot_df = df.groupby(['account', 'category', 'record_type'])['amount'].sum().reset_index()

    # 排序: 先排 Account (A-Z)，再排 Amount (大 -> 小)
    pivot_df = pivot_df.sort_values(by=['account', 'amount'], ascending=[True, False])
    
    # 格式化 amount (可選，保持小數點後2位)
    pivot_df['amount'] = pivot_df['amount'].round(2)

    # 為了輸出的美觀，把欄位名改回大寫 (Account, Category, RecordType, Amount)
    pivot_df.columns = ['Account', 'Category', 'RecordType', 'Amount']

    # 輸出
    print(f"正在寫入: {OUTPUT_FILE}")
    pivot_df.to_csv(OUTPUT_FILE, index=False, encoding='utf-8-sig')
    
    print("完成!")
    print("\n摘要預覽:")
    print(pivot_df.head(10))

if __name__ == "__main__":
    main()
