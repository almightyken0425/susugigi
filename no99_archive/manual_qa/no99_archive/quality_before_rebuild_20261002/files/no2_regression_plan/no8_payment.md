# 付費分冊

- 區碼 `PM`，對應整合層 Product Map 的 Payment
- 涵蓋付費牆顯示與價格載入、購買、恢復購買、功能閘控、授權解析與 LEVEL 呈現
- 其他分冊觸及付費閘只記閘在場，閘控流程本冊唯一承載

---

## PM-01 開啟付費牆與價格載入

- **QA metadata:**
    - feature_links: `app/payment`
    - risk_tags: `paywall`、`pricing`
    - capabilities: `manual-ui`、`jest-app`、`manual-device`
    - tier: `standard`
    - runtime_route: `none`
    - driver: `none`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 從設定頁升級入口開啟付費牆，載入動態價格至可購買狀態
- **規格依據:**
    - `no26_paywall_screen.md`
- **前置:**
    - 裝置為 LEVEL_0 且連網
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 開啟設定頁、點升級入口
    - 等待訂閱選項載入完成
    - 輪流點選年度與月度方案
    - 依序開啟隱私政策與使用條款
- **檢查點:**
    - **付費牆以 Modal 呈現，含功能列表、方案區、自動續訂揭露與頁腳連結**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 實作錨: `src/screens/Paywall/PaywallScreen.tsx`
    - **載入完成顯示動態年價與月價，預設選取年度方案並帶優惠標示**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no26_paywall_screen.md ## 佈局`
    - **載入中或未選方案時訂閱按鈕不可點按**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **隱私政策開啟官方支援頁，使用條款開啟 Apple 標準 EULA**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no26_paywall_screen.md ## 互動`
        - 實作錨: `src/screens/Paywall/PaywallScreen.tsx`、`src/constants/legal.ts`
    - **動態價格文案的組價與省額計算正確**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/screens/Paywall/paywallPricing.ts`
    - **法律連結固定為官方隱私頁與 Apple 標準 EULA**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/constants/legal.test.ts`

---

## PM-02 sandbox 購買訂閱即時生效與後端登記

- **QA metadata:**
    - feature_links: `app/payment`
    - risk_tags: `billing`、`entitlement`
    - capabilities: `manual-ui`、`jest-app`、`manual-device`
    - tier: `core`
    - runtime_route: `none`
    - driver: `none`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 從付費牆選方案完成 sandbox 購買，等級即時生效並關閉 Modal；後端登記落庫由後端分冊 CF-01 同場驗證
- **規格依據:**
    - `no26_paywall_screen.md ## 互動`
    - `no6_premium_logic.md ## startSubscriptionPurchase`
    - `no6_premium_logic.md ## handlePurchaseUpdate`
- **前置:**
    - 裝置已登入無有效訂閱的 sandbox 測試 Apple ID
    - sandbox 購買操作屬使用者 manual-ui
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 開啟付費牆並選定方案
    - 點訂閱按鈕，先於系統對話取消一次
    - 再點訂閱按鈕，完成 sandbox 購買確認
    - 回設定頁觀察升級入口
- **檢查點:**
    - **處理中按鈕顯示載入狀態且不可重複觸發**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **使用者取消不顯示購買失敗對話框，留在付費牆**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **購買成功即 StoreKit 生效，等級升過發起基準後 Modal 自動關閉**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **升級後設定頁升級入口自動隱藏**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: 無規格
        - 實作錨: `src/screens/Settings/SettingsScreen.tsx`
    - **Premium 商品回拋即升等並確認交易，登記與確認解耦、失敗互不阻斷**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/contexts/PremiumContext.tsx`
---

## PM-03 恢復購買同步 StoreKit

- **QA metadata:**
    - feature_links: `app/payment`
    - risk_tags: `restore-purchase`、`entitlement`
    - capabilities: `manual-ui`、`jest-app`、`manual-device`
    - tier: `extended`
    - runtime_route: `none`
    - driver: `none`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 從付費牆點恢復購買，查得有效購買即時生效、查無則提示，成敗本機判定
- **規格依據:**
    - `no26_paywall_screen.md ## 互動`
    - `no6_premium_logic.md ## reconcile`
    - `no6_premium_logic.md ## resolveTierFromPurchases`
- **前置:**
    - 曾完成 Premium 購買且訂閱有效的 sandbox Apple ID，供成功路徑
    - 無購買紀錄的 sandbox Apple ID，供查無路徑
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 以曾購買帳號重裝 app 後開啟付費牆，點恢復購買
    - 切換無購買帳號後再點恢復購買
- **檢查點:**
    - **操作中顯示載入狀態**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **查得 Premium 商品即時生效，顯示恢復成功對話框並解鎖上限**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **查無 Premium 商品顯示無可還原購買提示，等級不變**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **有效購買清單含 Premium 商品推定對應等級、否則 LEVEL_0**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/services/storeKitTier.ts`

---

## PM-04 LEVEL_0 配額閘控與升級解鎖

- **QA metadata:**
    - feature_links: `app/payment`
    - risk_tags: `quota-gate`、`entitlement`
    - capabilities: `manual-ui`、`jest-app`、`manual-device`
    - tier: `standard`
    - runtime_route: `none`
    - driver: `none`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** LEVEL_0 帳戶與類別觸頂被閘擋並導向付費牆，升級後上限解除
- **規格依據:**
    - `no17_subscription_gate_logic.md ## canUserPerformAction`
    - `no17_subscription_gate_logic.md ## LEVEL 規則表`
- **前置:**
    - LEVEL_0 裝置，帳戶總數已達 3、類別總數已達 7
    - 可完成 sandbox 購買供解鎖路徑
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 於帳戶列表嘗試新增第 4 個帳戶
    - 於類別列表嘗試新增第 8 個類別
    - 維持觸頂狀態新增一筆交易與一筆轉帳
    - 完成 sandbox 購買後重試新增帳戶與類別
- **檢查點:**
    - **帳戶觸頂新增被擋並導向付費牆**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 實作錨: `src/screens/Accounts/AccountListScreen.tsx`
    - **類別觸頂新增被擋並導向付費牆**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 實作錨: `src/screens/Categories/CategoryListScreen.tsx`
    - **總數等於上限時交易與轉帳仍允許新增**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no17_subscription_gate_logic.md ## LEVEL 規則表`
    - **規則矩陣正確：軟刪除排除計數、停用仍計數、LEVEL_1 以上全放行**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/services/subscriptionGateLogic.ts`
    - **升級後新增不再被擋，付費牆不再出現**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui

---

## PM-05 授權解析就緒與前景回落

- **QA metadata:**
    - feature_links: `app/payment`
    - risk_tags: `entitlement`、`foreground`
    - capabilities: `manual-ui`、`jest-app`、`qa-markers`、`manual-device`
    - tier: `extended`
    - runtime_route: `none`
    - driver: `none`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`、`qa-markers`

- **範圍:** 付費裝置冷啟動解析就緒不誤判，訂閱到期於前景刷新回落 LEVEL_0
- **規格依據:**
    - `no6_premium_logic.md ## 目的`
    - `no6_premium_logic.md ## reconcile`
- **前置:**
    - sandbox 訂閱有效的裝置；sandbox 週期壓縮、可等到自動到期
    - qa-markers 由實機 Debug console 擷取
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 完全關閉 app 後冷啟動，觀察啟動瞬間的等級呈現
    - 待 sandbox 訂閱到期，將 app 自背景恢復至前景
    - 重試觸頂新增動作
- **檢查點:**
    - **付費者冷啟動不閃現 LEVEL_0 誤判、不被導向付費牆**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **首次解析完成前不以佔位等級判定授權；查詢失敗維持現值、仍標記就緒**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/contexts/PremiumContext.tsx`
    - **到期後前景恢復觸發重新解析，等級回落、升級入口重新出現**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **QA PREMIUM 標記可見 reconcile 觸發與等級解析結果**
        - 層: 日誌 ／ 驗證者: Claude ／ 手段: qa-markers
        - 實作錨: `src/contexts/PremiumContext.tsx`

---

## PM-06 本機 StoreKit 商品與未成交購買

- **QA metadata:**
    - feature_links: `app/payment`
    - risk_tags: `billing`、`pricing`、`cancellation`
    - capabilities: `manual-ui`、`local-storekit`
    - tier: `extended`
    - runtime_route: `simulator`
    - driver: `sim-review`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`local-storekit`

- **範圍:** 分開判定商品價格、取消購買及非取消的購買失敗。
- **規格依據:** `no26_paywall_screen.md`、`no6_premium_logic.md ## startSubscriptionPurchase`
- **前置狀態:**
    - 設定頁或升級頁，免費版且沒有有效訂閱。錯誤設定依各情境準備，不需要先建立帳目。
    - 完成 [R15 環境準備](../no3_run_scripts/no17_r15_local_storekit.md#環境準備)。保留原生商店啟用及交易狀態證據，不以指定 Premium 等級取代。
- **操作步驟:**
    - 依[第 1 項：商品與價格](../no3_run_scripts/no17_r15_user_steps.md#1-商品與價格正確載入)執行，逐項核對起點、準備交接、操作結果及終點。
    - 依[第 2 項：取消購買](../no3_run_scripts/no17_r15_user_steps.md#2-取消購買後仍維持免費版)執行，逐項核對起點、準備交接、操作結果及終點。
    - 依[第 3 項：購買失敗與重試](../no3_run_scripts/no17_r15_user_steps.md#3-購買失敗後仍可重試)執行，逐項核對起點、準備交接、操作結果及終點。
- **檢查點:**
    - **月年商品與價格符合本機設定，選擇方案後購買按鈕可用**
        - 層: UI ／ 手段: manual-ui
        - 取證時點: 月費及年費各自選取後
        - 實作錨: `src/screens/Paywall/PaywallScreen.tsx`
    - **取消購買留在付費牆且維持免費，不顯示購買失敗對話框**
        - 層: UI ／ 手段: manual-ui
        - 取證時點: 每次取消起至回到設定頁，並核對可再次叫出購買視窗
        - 實作錨: `src/screens/Paywall/PaywallScreen.tsx`
    - **非取消購買錯誤顯示失敗提示，解除載入且未取得付費權益**
        - 層: UI ／ 手段: manual-ui
        - 取證時點: 失敗提示關閉後、商店無有效訂閱及恢復正常後重試時
        - 實作錨: `src/screens/Paywall/PaywallScreen.tsx`
- **結束狀態與清理:**
    - 設定頁維持免費，沒有新增帳目。購買錯誤設定已關閉，可接 PM-08 的查無分支。
    - 若本輪在本項結束，依 [R15 還原](../no3_run_scripts/no17_r15_local_storekit.md#還原)清理。功能結果與清理結果分開。

---

## PM-07 本機月年訂閱與啟動恢復

- **QA metadata:**
    - feature_links: `app/payment`
    - risk_tags: `billing`、`entitlement`、`cold-start`
    - capabilities: `manual-ui`、`local-storekit`
    - tier: `extended`
    - runtime_route: `simulator`
    - driver: `sim-review`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`local-storekit`

- **範圍:** 月費及年費各自從免費版購買成功，確認解鎖新增與重開後的權益及資料。
- **規格依據:** `no6_premium_logic.md ## handlePurchaseUpdate`、`no6_premium_logic.md ## reconcile`、`no26_paywall_screen.md`
- **前置狀態:**
    - 每種方案均從沒有有效訂閱的免費版開始。資料為 R15 的 3 帳戶、7 類別、基準支出及轉帳，先取得帳目與餘額比對值。
    - 完成 [R15 環境準備](../no3_run_scripts/no17_r15_local_storekit.md#環境準備)。保留原生商店啟用及交易狀態證據，不以指定 Premium 等級取代。
- **操作步驟:**
    - 依[第 5 項：月費購買與重開](../no3_run_scripts/no17_r15_user_steps.md#5-月費購買成功重開後保留權益與帳目)執行，逐項核對起點、準備交接、操作結果及終點。
    - 依[第 6 項：年費購買與重開](../no3_run_scripts/no17_r15_user_steps.md#6-年費購買成功重開後保留權益與帳目)執行，逐項核對起點、準備交接、操作結果及終點。
- **檢查點:**
    - **月訂閱成功後升級頁關閉，設定頁升級入口消失且第 4 帳戶與第 8 類別可新增**
        - 層: UI ／ 手段: manual-ui
        - 取證時點: 月費購買成功且第 4 帳戶及第 8 類別新增後
        - 實作錨: `src/contexts/PremiumContext.tsx`
    - **年訂閱成功後升級頁關閉，設定頁升級入口消失且第 4 帳戶與第 8 類別可新增**
        - 層: UI ／ 手段: manual-ui
        - 取證時點: 年費購買成功且第 4 帳戶及第 8 類別新增後
        - 實作錨: `src/contexts/PremiumContext.tsx`
    - **兩種有效訂閱冷啟動均自動恢復付費權益，不誤開付費牆且帳目保留**
        - 層: UI ／ 手段: manual-ui
        - 取證時點: 第 5 與第 6 項各自受控重開並核對設定及資料後
        - 實作錨: `src/contexts/PremiumContext.tsx`
- **結束狀態與清理:**
    - 年費有效。刪除未使用的測試帳戶 4 與測試類別 8，回到 3 帳戶及 7 類別，原有帳目保留。PM-08 成功分支先重設商店。
    - 若本輪在本項結束，依 [R15 還原](../no3_run_scripts/no17_r15_local_storekit.md#還原)清理。功能結果與清理結果分開。

---

## PM-08 本機手動恢復購買

- **QA metadata:**
    - feature_links: `app/payment`
    - risk_tags: `restore-purchase`、`entitlement`
    - capabilities: `manual-ui`、`local-storekit`
    - tier: `extended`
    - runtime_route: `simulator`
    - driver: `sim-review`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`local-storekit`

- **範圍:** 實際點按還原購買，分開判定查無及成功分支。啟動時自動恢復由 PM-07 判定。
- **規格依據:** `no26_paywall_screen.md ## 互動`、`no6_premium_logic.md ## reconcile`
- **前置狀態:**
    - 查無分支為免費版且沒有有效訂閱。成功分支須同時具備有效月費交易、可見的還原按鈕及 R15 共用資料。
    - 完成 [R15 環境準備](../no3_run_scripts/no17_r15_local_storekit.md#環境準備)。保留原生商店啟用及交易狀態證據，不以指定 Premium 等級取代。
- **操作步驟:**
    - 依[第 4 項：沒有購買紀錄時還原](../no3_run_scripts/no17_r15_user_steps.md#4-沒有購買紀錄時按還原購買)執行，逐項核對起點、準備交接、操作結果及終點。
    - 依[第 7 項：點按還原成功](../no3_run_scripts/no17_r15_user_steps.md#7-點還原購買後恢復付費權益)執行，逐項核對起點、準備交接、操作結果及終點。
    - 成功分支依 R15 還原成功前置準備。若按鈕已隱藏，保持未驗，不以清帳目、重裝或 mockTier 強造入口。
- **檢查點:**
    - **手動恢復查無有效訂閱時提示無可還原購買，等級維持免費**
        - 層: UI ／ 手段: manual-ui
        - 取證時點: 查無提示關閉、再次點按及回到設定頁後
        - 實作錨: `src/screens/Paywall/PaywallScreen.tsx`
    - **手動點按恢復查得有效商品時提示成功並解除上限，不能以自動恢復代驗**
        - 層: UI ／ 手段: manual-ui
        - 取證時點: 實際點按後出現成功提示，並完成第 4 帳戶及第 8 類別新增時
        - 實作錨: `src/screens/Paywall/PaywallScreen.tsx`
- **結束狀態與清理:**
    - 查無分支仍為免費。成功分支為有效月費，刪除未使用的測試帳戶與類別後，回到 3 帳戶及 7 類別，可接 PM-09。
    - 若本輪在本項結束，依 [R15 還原](../no3_run_scripts/no17_r15_local_storekit.md#還原)清理。功能結果與清理結果分開。

---

## PM-09 本機訂閱到期與免費額度

- **QA metadata:**
    - feature_links: `app/payment`
    - risk_tags: `expiry`、`quota-gate`、`data-preservation`
    - capabilities: `manual-ui`、`local-storekit`
    - tier: `extended`
    - runtime_route: `simulator`
    - driver: `sim-review`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`local-storekit`

- **範圍:** 真正到期後判定回免費、重開、資料保留及各種免費額度邊界。
- **規格依據:** `no6_premium_logic.md ## reconcile`、`no17_subscription_gate_logic.md`
- **前置狀態:**
    - 有效月費，3 帳戶及 7 類別，帳目符合 R15 月年購買前基準。後續依序建立 4／8、4／7 及 3／8 的帳戶與類別組合。
    - 完成 [R15 環境準備](../no3_run_scripts/no17_r15_local_storekit.md#環境準備)。保留原生商店啟用及交易狀態證據，不以指定 Premium 等級取代。
- **操作步驟:**
    - 依[第 8 項：到期及恰好上限](../no3_run_scripts/no17_r15_user_steps.md#8-到期後回到免費版達上限仍可記帳)執行，逐項核對起點、準備交接、操作結果及終點。
    - 依[第 9 項：兩種數量都超額](../no3_run_scripts/no17_r15_user_steps.md#9-帳戶與類別同時超額原資料保留且新增紀錄被擋)執行，逐項核對起點、準備交接、操作結果及終點。
    - 依[第 10 項：只有帳戶超額](../no3_run_scripts/no17_r15_user_steps.md#10-只有帳戶超額也會限制新增紀錄)執行，逐項核對起點、準備交接、操作結果及終點。
    - 依[第 11 項：只有類別超額](../no3_run_scripts/no17_r15_user_steps.md#11-只有類別超額也會限制新增紀錄)執行，逐項核對起點、準備交接、操作結果及終點。
    - 依[第 12 項：停用與刪除](../no3_run_scripts/no17_r15_user_steps.md#12-停用不退還名額刪除後恢復新增)執行，逐項核對起點、準備交接、操作結果及終點。
    - 每次回到 App 前先取得該次到期證據。清空購買紀錄不算到期。保留各項資料基準及超額組合的獨立結果。
- **檢查點:**
    - **已到期且無其他有效訂閱時，回前景轉為免費並重新顯示升級入口**
        - 層: UI ／ 手段: manual-ui
        - 取證時點: 第 8 項取得到期證據且回到前景後
        - 實作錨: `src/services/subscriptionGateLogic.ts`
    - **到期後冷啟動仍為免費，沒有沿用過期付費狀態**
        - 層: UI ／ 手段: manual-ui
        - 取證時點: 第 8 項完全關閉後受控重開並查看設定時
        - 實作錨: `src/services/subscriptionGateLogic.ts`
    - **降級前後既有帳目與餘額一致，超額帳戶及類別仍保留可查看**
        - 層: UI ／ 手段: manual-ui
        - 取證時點: 第 8 與第 9 項到期前後逐項比對資料時
        - 實作錨: `src/services/subscriptionGateLogic.ts`
    - **恰好三帳戶七類別時新增帳戶類別被擋，新增交易與轉帳仍可完成**
        - 層: UI ／ 手段: manual-ui
        - 取證時點: 第 8 項分別測新增帳戶、類別、支出與轉帳後
        - 實作錨: `src/services/subscriptionGateLogic.ts`
    - **帳戶與類別同時超額或僅其中一種超額時，新增交易與轉帳均被付費牆攔住**
        - 層: UI ／ 手段: manual-ui
        - 取證時點: 第 9、10、11 項各自完成支出及轉帳被擋的檢查後
        - 實作錨: `src/services/subscriptionGateLogic.ts`
    - **停用超額項目不退額度，軟刪除回到上限後可新增交易與轉帳**
        - 層: UI ／ 手段: manual-ui
        - 取證時點: 第 12 項分別完成停用後仍被擋及刪除後可新增時
        - 實作錨: `src/services/subscriptionGateLogic.ts`
- **結束狀態與清理:**
    - 免費版，3 帳戶及 7 類別。保留原有及步驟中新建的帳目，符合 R15 最終餘額基準。整場結束後依 R15 還原段清理。
    - 若本輪在本項結束，依 [R15 還原](../no3_run_scripts/no17_r15_local_storekit.md#還原)清理。功能結果與清理結果分開。
