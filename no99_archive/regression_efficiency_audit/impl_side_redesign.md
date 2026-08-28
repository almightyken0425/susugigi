# impl 與機制層改造方案

本方案把三層盤查的 findings 轉成可直接動工的施工單。路徑一律以 git root 為錨：impl 指 `~/Doc/ai-company/product/susugigi/no5_product_development/no2_accounting_app`，backend 指 `~/Doc/ai-company/product/susugigi/no5_product_development/no3_cloud_functions/functions`，quality 指 `~/Doc/ai-company/product/susugigi/no6_product_quality/no2_accounting_app`，設定 repo 指 `~/.claude`。

施工單分六包，包與包之間有順序相依，最後一節逐項標 git 與層。

---

## marker 補齊清單

### 通則

- 前端 marker 一律套 `__DEV__` 閘。`__DEV__` 是編譯期常數，release 下 metro 替成 false、整段被 minifier 消掉，字串不進 bundle。
- 後端無 `__DEV__` 概念，Cloud Logging 本身有存取控制，uid 與 otid 可直接印。
- 新增命名空間 `QA RATE` 必須同批寫進 quality 的 `no1_capability_profile.md` 命名空間清單，否則腳本一引用，check_plan 第 5 項就報缺。
- 每條 marker 的效果分三態，寫在該條末尾：修好已宣告卻做不出來的手段、讓既有 manual-ui 檢查點多一條日誌層檢查點、純診斷鋪路列不改分冊。誠實分類的理由是分冊檢查點帶層欄位，把 UI 層檢查點硬改掛 qa-markers 會讓層與手段互相矛盾。

### MRK-01 加 MRK-02：QA BOOT 帶 uid 與去重分支

- 落點一：impl `src/contexts/AuthContext.tsx`，`handleAuthEvent` 的 `authUser` 分支入口，緊接在 `const pending = await readPendingAccountDeletion();` 之前。
- 落點二：同檔 `postAuthRef` 去重三分支，即 `const entry = postAuthRef.current;` 起的整段。
- 落點三：impl `src/navigation/AppNavigator.tsx:179` 既有 resolve 列後綴 uid。該處 `user` 已在 scope，effect 的守門條件就含 `!user`。
- 命名空間：`QA BOOT`。
- 欄位：`uid` 取前八碼、`hasUser`、`dedup`、`reason`。

```ts
// AuthContext.tsx — handleAuthEvent 的 authUser 分支入口
if (__DEV__) {
  console.log(`QA BOOT authEvent uid=${authUser.uid.slice(0, 8)} hasUser=true`);
}
const pending = await readPendingAccountDeletion();
```

```ts
// AuthContext.tsx — postAuthRef 去重三分支
const entry = postAuthRef.current;
if (entry && entry.uid === authUser.uid) {
  if (__DEV__) {
    console.log(`QA BOOT authEvent uid=${authUser.uid.slice(0, 8)} dedup=true reason=same_uid`);
  }
  const ok = await entry.promise;
  if (!ok && postAuthRef.current === null) {
    if (__DEV__) {
      console.log(`QA BOOT authEvent uid=${authUser.uid.slice(0, 8)} dedup=false reason=retry_after_fail`);
    }
    await startPostAuth(authUser);
  }
} else {
  if (__DEV__) {
    console.log(`QA BOOT authEvent uid=${authUser.uid.slice(0, 8)} dedup=false reason=new_uid`);
  }
  await startPostAuth(authUser);
}
```

```ts
// AppNavigator.tsx:179 — 原列後綴 uid，其餘不動
if (__DEV__) {
  console.log(
    `QA BOOT resolve premiumLoaded=${isPremiumLoaded} landing=${launchMode} uid=${user.id.slice(0, 8)}`,
  );
}
```

- 效果：修好已宣告卻做不出來的手段。R01 序 9 全程僅一顆 uid 與序 13 uid 前八碼與前記一致兩條斷言，都點名 grep `QA BOOT` 列，補完才 grep 得到。`dedup=true` 是 AU-03 去重的正向輸出，讓去重確實發生，與 Metro 沒帶 `--client-logs` 導致整批 marker 不落檔，兩種情況分得開。
- 連帶：R01 序 11 與 R12 序 2、序 8 不點名命名空間、使用者讀 `QA RCACHE` 的 uid 即可，維持原樣不改。分冊 `no1_auth_bootstrap.md` 第 90 行的驗證者欄與 csv 序 13 不一致，同批對齊成 Claude。

### MRK-03：資料清除中斷復原五分支

- 落點：impl `src/contexts/AuthContext.tsx` 的 pending 區段五個分支，加上 `finalizeAccountDeletionCleanup` 收尾，加上 `src/services/localDbService.ts` 的 `destroyUserData`。
- 命名空間：`QA BOOT`，動作名 `erase`。
- 欄位：`branch`、`stage`、`uid`、`purged`、`flagCleared`、`tables`、`rows`。

```ts
// 五個分支各一行，branch 值依序為 inflight / done_cleanup / probe_gone / probe_unknown / suppress_rebirth
if (__DEV__) {
  console.log(
    `QA BOOT erase branch=inflight stage=${pending.stage} uid=${pending.uid.slice(0, 8)}`,
  );
}
```

```ts
// finalizeAccountDeletionCleanup 收尾，purged 與 flagCleared 都要外顯
const finalizeAccountDeletionCleanup = useCallback(async (uid: string): Promise<void> => {
  let purged = false;
  let flagCleared = false;
  try {
    await destroyUserData(uid);
    purged = true;
  } catch (e) {
    console.error('Data-erase local purge failed', e);
  }
  if (purged) {
    try {
      await clearPendingAccountDeletion();
      flagCleared = true;
    } catch (e) {
      console.error('Data-erase flag clear failed', e);
    }
  }
  if (__DEV__) {
    console.log(
      `QA BOOT erase purge uid=${uid.slice(0, 8)} purged=${purged} flagCleared=${flagCleared}`,
    );
  }
}, []);
```

```ts
// localDbService.ts destroyUserData — batch 送出前印實刪量
if (__DEV__) {
  console.log(
    `QA BOOT erase destroy uid=${userId.slice(0, 8)} tables=${USER_SCOPED_TABLES.length} rows=${batchOps.length}`,
  );
}
```

- 效果：純診斷鋪路列不改分冊。AS-07 既有檢查點的手段維持不動。R12 的 csv 加一列 Claude 節點 grep `QA BOOT erase`，已驗欄留空。走錯任一分支的後果分別是資料遺失、卡重試畫面、雲端孤兒，現場沒有 branch 值就只能靠畫面猜。

### MRK-04：後端 deleteUserAccount 成功路徑與墓碑收尾

- 落點：backend `src/handlers/deleteUserAccount.ts` 第 79 行與第 81 行。
- 命名空間：無，走 Cloud Logging 純文字。
- 欄位：`uid`、`appleRevokeFailed`、`providers`。

```ts
await markDeletionCompleted(uid).catch(e =>
  console.warn(`deleteUserAccount 墓碑收尾失敗 uid=${uid}`, e),
);
console.info(
  `deleteUserAccount 完成 uid=${uid} appleRevokeFailed=${appleRevokeFailed} providers=${providerIds.join('/')}`,
);
return { ok: true, appleRevokeFailed };
```

- 效果：修好已宣告卻做不出來的手段。分冊 `no6_app_setting.md:184` 寫 Cloud Logging 有 deleteUserAccount 執行完成訊息，在應用層本來沒有對應輸出。uid 讓這條 log 與 R12 序 11 的 firestore-read 墓碑查詢對得起來；墓碑收尾失敗原本被 `.catch(() => undefined)` 整個吞掉，補上後與下一列的墓碑檢查點形成閉環。

### MRK-05：capBilling 進入點與四個提前 return

- 落點：backend `src/handlers/capBilling.ts` 函式入口與第 20、23、28、34 行。
- 欄位：`cost`、`budget`、`reason`。

```ts
console.info(`capBilling 收到訊息 cost=${data?.costAmount} budget=${data?.budgetAmount}`);
// 四個 return 各補一行，reason 依序為 missing_fields / under_budget / no_project / already_disabled
console.info('capBilling 不動作 reason=under_budget');
return;
```

- 效果：修好已宣告卻做不出來的手段。CF-04 的未超標訊息觸發函式執行後直接結束這條斷言，目前在應用層恆為沒有錯誤，Pub/Sub 沒接上與接上且正確不動作分不出來，屬穩過的假訊號。
- 判讀注意：這支帶 `retry:true`，重試會重印同一組 info。log 判讀以 reason 為準，不以出現次數為準，這句要寫進 R12 序 14 的說明欄。

### MRK-06：verifyTransaction 成功登記與六個拒絕分支

- 落點：backend `src/handlers/verifyTransaction.ts` 第 75 行的 return 之前，以及第 21、26、32、46、49、56 行的六個 throw 之前。
- 欄位：`uid`、`otid`、`tier`、`env`、`reason`。

```ts
console.info(
  `verifyTransaction 登記完成 uid=${uid} otid=${originalTransactionId} tier=${derived.tier} env=${environment}`,
);
return { ok: true };
// 六個 throw 前各一行，reason 依序為
// unauthenticated / missing_jws / missing_otid / tombstone / no_user / no_status
console.warn('verifyTransaction 拒絕 reason=tombstone');
```

- 效果：修好已宣告卻做不出來的手段。CF-01 的 verifyTransaction 執行成功前半句原本驗不到，因為 client 兩處呼叫都是 fire-and-forget 加 `.catch`，沒送出與送出成功在 log 上同形。`otid` 與 `tier` 正是同測項另一條 firestore-read 檢查點要比對的 entitlements 欄位，log 與雲端資料可互相對錶。
- 拒絕分支那條檢查點的手段維持 jest-backend、不改分冊，reason 列純為 R10 現場診斷。

### MRK-07：writeEntitlement 兩道閘

- 落點：backend `src/services/entitlementStore.ts` 第 25 行與第 39 行的 `return false` 之前。
- 欄位：`uid`、`reason`、`stored`、`incoming`。

```ts
console.info(`writeEntitlement 略過 uid=${uid} reason=tombstone`);
return false;
// 單調防護那道
console.info(
  `writeEntitlement 略過 uid=${uid} reason=stale_signed_date stored=${storedSignedDate} incoming=${signedDate}`,
);
return false;
```

- 效果：純診斷鋪路列不改分冊。CF-02 與 CF-03 的手段維持 jest-backend。價值在 R11 這場實機加 sandbox 自然到期的 50 分鐘場次：授權沒更新時，通知沒到、被墓碑擋、被亂序擋三種可能原本一條線索都沒有。`stored` 與 `incoming` 是單調防護唯一的判準，印出來才分得出防護正確生效與 signedDate 取錯欄位。

### MRK-08：訂閱閘門 QA PAYWALL gate

- 落點：impl `src/services/subscriptionGateLogic.ts` 的 `canUserPerformAction`。
- 命名空間：`QA PAYWALL`。
- 欄位：`action`、`tier`、`accounts`、`categories`、`limit`、`op`、`allowed`、`reason`。
- 重要限制：`accCount` 與 `catCount` 是各 case 區塊內的區域變數，不能塞進單一 return 前的共用 log 行，必須各 case 各印一條。

```ts
if (currentTier >= PlanTier.LEVEL_1) {
  if (__DEV__) {
    console.log(`QA PAYWALL gate action=${actionId} tier=${PlanTier[currentTier]} allowed=true reason=tier_unlimited`);
  }
  return true;
}

switch (actionId) {
  case 'createAccount': {
    if (!userId) {
      if (__DEV__) { console.log(`QA PAYWALL gate action=${actionId} allowed=false reason=no_user_id`); }
      return false;
    }
    const accCount = await countActiveAccounts(userId);
    const allowed = accCount < MAX_FREE_ACCOUNTS;
    if (__DEV__) {
      console.log(
        `QA PAYWALL gate action=createAccount tier=${PlanTier[currentTier]} accounts=${accCount} limit=${MAX_FREE_ACCOUNTS} op=lt allowed=${allowed}`,
      );
    }
    return allowed;
  }
  // createCategory 同形，欄位換成 categories 與 MAX_FREE_CATEGORIES
  case 'createTransaction':
  case 'createTransfer': {
    if (!userId) {
      if (__DEV__) { console.log(`QA PAYWALL gate action=${actionId} allowed=false reason=no_user_id`); }
      return false;
    }
    const [accCount, catCount] = await Promise.all([
      countActiveAccounts(userId),
      countActiveCategories(userId),
    ]);
    const allowed = accCount <= MAX_FREE_ACCOUNTS && catCount <= MAX_FREE_CATEGORIES;
    if (__DEV__) {
      console.log(
        `QA PAYWALL gate action=${actionId} tier=${PlanTier[currentTier]} accounts=${accCount} limit=${MAX_FREE_ACCOUNTS} categories=${catCount} catLimit=${MAX_FREE_CATEGORIES} op=lte allowed=${allowed}`,
      );
    }
    return allowed;
  }
}
```

- 效果：讓既有 manual-ui 檢查點多一條日誌層檢查點。PM-04 的四條 manual-ui 檢查點維持不動，另在 `no8_payment.md` 的 PM-04 新增一條層為日誌、手段為 qa-markers 的檢查點，斷言講閘門輸出 tier、計數、上限與 allowed，等於上限時交易轉帳 op 為 lte 且 allowed 為 true。這條把邊界刻意不對稱這件事變成可機械驗的東西：建立類用 `<`、記錄類用 `<=`。
- 連帶：`QA PAYWALL` 目前只有 `PaywallScreen.tsx:272` 一條 overflow marker、零 csv 引用。加進來要同步在 R10 序 8、9、11、19 之後補 Claude 節點列，否則沒人讀。
- 額外收獲：三處 `!userId` 保守擋下原本與觸頂被擋長得完全一樣，`reason=no_user_id` 把它們分開。

### MRK-09：QA RATE convert

- 落點：impl `src/contexts/CurrencyContext.tsx` 的 `convertAmount`，夾在 `pickLatestEffectiveRate` 與 `resolveRateFromRecord` 取值之後、`return` 之前。不要掛在 `currencyService.resolveCurrencyRate`，那條路徑搆不到 CU-05 這條斷言。
- 命名空間：`QA RATE`，新增。
- 欄位：`from`、`to`、`rate`、`direction`、`pickedDate`。
- 必須去重：`convertAmount` 每列渲染都呼叫，R05 序 19 切到全部期間會刷爆 log。以 module 級 Set 依 `幣別 id 加 factor` 做鍵，同組合本 session 只印一次。

```ts
// CurrencyContext.tsx 檔案層級
const qaRateSeen = __DEV__ ? new Set<string>() : null;

// convertAmount 內，factor 取得之後
if (__DEV__ && qaRateSeen) {
  const key = `${fromId}:${factor}`;
  if (!qaRateSeen.has(key)) {
    qaRateSeen.add(key);
    const direction = matchRate
      ? matchRate.currencyFromId === fromId ? 'direct' : 'inverse'
      : 'fallback1';
    const pickedDate = matchRate
      ? new Date(Number((matchRate._raw as any).date)).toISOString()
      : 'none';
    console.log(
      `QA RATE convert from=${fromCurrencyCode} to=base rate=${factor} direction=${direction} pickedDate=${pickedDate}`,
    );
  }
}
return amount * factor;
```

- 效果：讓既有 manual-ui 檢查點多一條日誌層檢查點。`no5_currency.md:153` 的 CU-05 維持 manual-ui，另加一條日誌層 qa-markers 檢查點。現場原本只看得到 978 TWD 一個數字，補完後看得到匯率值、正逆向、取到哪一筆生效日期，四個維度全出來。
- 分冊 `no5_currency.md:87` 與 `:131` 兩條手段維持 jest-app、不改，它們已由 R00 序 8 收下。
- 同批要件：`QA RATE` 進 `no1_capability_profile.md` 命名空間清單；R05 序 20 後補一列 Claude 節點。

### MRK-10：QA SCHED split 與 truncate

- 落點：impl `src/services/recurringLogic.ts` 的 `updateSchedule` 與 `deleteSchedule`。
- 命名空間：`QA SCHED`。

```ts
// updateSchedule 的 FUTURE 分支，batch 送出後
if (__DEV__) {
  console.log(
    `QA SCHED split oldScheduleId=${schedule.id} oldEndOn=${newEndOn} newScheduleId=${newSchedule.id} generated=${generatedCount}`,
  );
}
// deleteSchedule 的 FUTURE 分支
if (__DEV__) {
  console.log(
    `QA SCHED truncate scheduleId=${schedule.id} endOn=${newEndOn} softDeleted=${softDeletedCount}`,
  );
}
```

- 效果：純診斷鋪路列不改分冊。RC-04 與 RC-05 那五條斷言的手段是 jest-app，補 marker 不能讓它們成立。真正的缺口是這兩支函式全 repo 零測試呼叫，修法見測試修正清單的第一條。marker 只供 R04 序 9 至 11 出狀況時定位。

### MRK-11：匯入略過七條分支統一成 QA VALID

- 落點：impl `src/services/importService.ts` 的七個 `skipped++`，即第 700、720、744、756、773、800、823 行附近。其中 720 與 773 目前完全靜默，其餘五條是格式各異的裸 `console.warn`。
- 命名空間：`QA VALID`，動作名 `importRow`。
- 與 DEV-04 同批做：改寫的同時移除原本的裸 warn。

```ts
// 交易列 getRowSkipReason 命中
if (rowSkipReason) {
  if (__DEV__) {
    console.log(`QA VALID reject op=importRow mode=${mode} row=${i} reason=${rowSkipReason}`);
  }
  skipped++;
  continue;
}

// 交易列實體對不上，原本完全靜默
if (!accountId || !categoryId) {
  if (__DEV__) {
    console.log(
      `QA VALID reject op=importRow mode=${mode} row=${i} reason=entity_unmapped account=${accountName}:${currencyCode} category=${categoryKey}`,
    );
  }
  skipped++;
  continue;
}

// 轉帳列實體對不上，原本完全靜默
if (!fromAccountId || !toAccountId) {
  if (__DEV__) {
    console.log(
      `QA VALID reject op=importRow mode=${mode} row=${i} reason=entity_unmapped from=${fromAccountName}:${fromCurrency} to=${toAccountName}:${toCurrency}`,
    );
  }
  skipped++;
  continue;
}

// 跨幣別缺轉入金額，原本印使用者金額原字串
if (isCrossCurrency && !hasToAmount) {
  if (__DEV__) {
    console.log(`QA VALID reject op=importRow mode=${mode} row=${i} reason=missing_to_amount`);
  }
  skipped++;
  continue;
}
```

- 兩條 catch 後備維持 `console.warn`，但只印 error 物件、不印列內容。
- 迴圈目前用 `for (const row of data)`，要拿到 `row` 索引需改成 `data.forEach` 或 `for (let i = 0; ...)`；改法擇一、同批做完。
- 效果：讓既有 manual-ui 檢查點多一條日誌層檢查點。`no6_app_setting.md:125` 的送出成功顯示已匯入與略過筆數維持 manual-ui，另加一條日誌層 qa-markers 檢查點，斷言講每一筆略過都有 reason，略過筆數等於 reject 列數。略過數對不上時最常見成因正是那兩條原本靜默的實體對不上分支。
- `no6_app_setting.md:127` 金額超界那條手段維持 jest-app、不改。
- `QA VALID` 目前零 csv 引用，要在 R10 匯入段補一列 Claude 節點才有人讀。

### MRK-12：QA PREF hydrate

- 落點：impl `src/contexts/HomeFilterContext.tsx` 的 `hydrate`，在 `if (hydrationSucceeded) { hydratedForUid.current = user.id; }` 之前。
- 命名空間：`QA PREF`。
- 寫回守門那段不加 marker，選取變更會高頻觸發。

```ts
if (cancelled) { return; }
if (__DEV__) {
  console.log(
    `QA PREF hydrate uid=${user.id.slice(0, 8)} hydrated=${hydrationSucceeded} granularity=${granularity ?? 'fallback'} group=${mode ?? 'fallback'} accounts=${ids?.length ?? 'fallback'}`,
  );
}
if (hydrationSucceeded) { hydratedForUid.current = user.id; }
```

- 三個 sanitize 結果目前宣告在 `if (rows.length > 0)` 區塊內，要提到 `hydrate` 函式頂層才印得到；提升時維持原本的 `undefined` 初值語意。
- 效果：讓既有 manual-ui 檢查點多一條日誌層檢查點，但範圍要收窄。HD-02 的三值保留半有更便宜的路：sqlite-local 已解阻，直接查 settings 的 `home_time_granularity`、`home_group_mode`、`home_selected_account_ids` 三欄即可，R06 序 8 後補一列 Claude 節點跑查詢器，不必動 impl。只有讀取失敗不寫回這條路徑 sqlite 看不到，marker 是唯一手段。

### MRK-14：schema migration 事件

- 落點：impl `src/database/adapter.native.ts`。
- 命名空間：`QA BOOT`。
- WatermelonDB 0.28 的 `SQLiteAdapter` 有公開 `migrationEvents`，兩個 callback 不帶參數、拿不到 from 版本，但有沒有跑 migration 與跑完有沒有成功，正是 LD-01 要分辨的兩件事。

```ts
import SQLiteAdapter from '@nozbe/watermelondb/adapters/sqlite';
import { schema } from './schema';
import migrations from './migrations';

export const adapter = new SQLiteAdapter({
    schema,
    migrations,
    jsi: true,
    migrationEvents: {
        onStart: () => {
            if (__DEV__) { console.log('QA BOOT schema migrationStart'); }
        },
        onSuccess: () => {
            if (__DEV__) { console.log(`QA BOOT schema migrationSuccess version=${schema.version}`); }
        },
    },
    onSetUpError: error => {
        console.error('Database setup failed', error);
    },
});

if (__DEV__) {
    console.log(`QA BOOT schema version=${schema.version} tables=${Object.keys(schema.tables).length}`);
}
```

- 效果：讓既有 manual-ui 檢查點多一條日誌層檢查點。`no9_local_database.md:21` 的 LD-01 維持 manual-ui，另加一條日誌層 qa-markers 檢查點：沒印 migrationStart 代表靜默停在舊版，印了 Start 沒印 Success 就是中途失敗。R01 序 3 後補一列 Claude 節點 grep 這三個字串。
- 不可行的做法：拿 R01 序 1 舊版與序 3 新版兩次 log 做對照。序 1 跑的是舊 build，不含新加的 marker。
- 更強的落庫證據是 `PRAGMA user_version`，見工具強化的 query_local_db 段。

### MRK-15：QA FINDING 除名與 check_plan 抽取修正

- `QA FINDING` 從來不是 marker，在 impl 只出現在 `src/services/cleanupScheduleStamps.ts:10` 的一句程式註解裡。
- 動作一：quality `no1_capability_profile.md` 第 54 行的命名空間清單刪掉 `QA FINDING`。
- 動作二：check_plan 第 5 項的 impl 側抽取改成只認真的 console 呼叫，見工具強化段。
- 不要做的事：為了讓 `QA DBQ`、`QA PAYWALL`、`QA RCACHE`、`QA UNDO`、`QA VALID` 五個零引用命名空間有人用，就去 R06、R07 補列收 HD-05 與 RC-07 的檢查點。那幾條檢查點的手段是 jest-app、已由 R00 序 9 與序 10 收下，再收一次是重複登載且與分冊手段欄矛盾。要用那些 marker 的正確做法是加已驗欄留空的鋪路列。

---

## `__DEV__` 閘修正清單

### 該加閘的

以下逐條給檔名行號、現行寫法、改後寫法。改後寫法一律是同一行外包 `if (__DEV__) { ... }`，此處只列現行內容以便逐條核對。

- impl `src/services/syncEngine.ts:102` — 現行 `console.log('🔄 [SyncEngine] Sync already in progress, skipping.');`
- impl `src/services/syncEngine.ts:138` — 現行 `console.log('⏱️ [SyncEngine] Sync cooldown active, skipping. ${remainingSec}s left.');`
- impl `src/services/syncEngine.ts:144` — 現行 `console.log('📴 [SyncEngine] Offline, skipping sync.');`
- impl `src/services/syncEngine.ts:204` — 現行 `console.log('✅ [SyncEngine] Sync Complete!');`
- impl `src/services/syncEngine.ts:272` — 現行 `console.log('🔁 [SyncEngine] Adopted legacy device watermark into per-user Settings.');`
- impl `src/services/syncEngine.ts:305` — 現行 `console.log('📦 [SyncEngine] Running InitialBackup (full upload)...');`
- impl `src/services/syncEngine.ts:311` — 現行 `console.log('✅ [SyncEngine] InitialBackup complete.');`
- impl `src/services/syncEngine.ts:358` — 現行 `console.log('🚀 [SyncEngine] Committed batch of ${batchOpCount} writes.');`
- impl `src/services/syncEngine.ts:388` — 現行 `console.log('✅ [SyncEngine] Total Pushed: ${opCount} changes.');`
- impl `src/services/syncEngine.ts:414` — 現行 `console.log('📊 [SyncEngine] Found ${count} changes since ${since}');`，`since` 是 per-user 同步水位時間戳
- impl `src/services/userService.ts:155` — 現行 `console.log('✅ [PrefUpload] Create user doc server-acked'),`，屬 then 回呼參數，包閘要改成箭頭函式體
- impl `src/services/userService.ts:167` — 現行 `console.log('✅ [PrefUpload] Fallback update server-acked (profile + prefs persisted)'),`，同上
- impl `src/services/userService.ts:172` — 現行 `console.log('✅ [Firestore] Create user document queued');`
- impl `src/services/userService.ts:178` — 現行 `console.log('✅ [PrefUpload] Merge update server-acked (profile + prefs persisted)'),`，同 155
- impl `src/services/userService.ts:182` — 現行 `console.log('✅ [Firestore] Update user document queued');`
- impl `src/services/userService.ts:220` — 現行 `console.log('✅ [PrefUpload] Preferences uploaded (server acked)');`
- impl `src/services/userService.ts:364` — 現行為三行的 `console.log`，內容揭露雲端帳號文件存在與否，每次登入都印
- impl `src/screens/Settings/CurrencyRateEditorScreen.tsx:161` — 現行 `console.log('[SaveRate] from=${currencyFromId} to=${currencyToId} rate=${rate} date=${rateDate.toISOString()}');`。改法二擇一：套閘，或直接改寫成 MRK-09 的 `QA RATE` 格式順便補上匯率建立路徑的 marker 缺口
- impl `src/services/importService.ts:699` — 現行 `console.warn('Skipping transaction row:', rowSkipReason);`，與 MRK-11 同批改寫成 `QA VALID`
- impl `src/services/importService.ts:755` — 現行 `console.warn('Skipping transfer row:', rowSkipReason);`，同上
- impl `src/services/importService.ts:799` — 現行 `console.warn('Cross-currency transfer missing toAmount, skipping:', fromAmountStr);`，`fromAmountStr` 是使用者匯入檔的金額原字串，改寫時換成 `reason=missing_to_amount`、不帶值
- impl `src/services/importService.ts:743` 與 `:822` — 現行 `console.warn('Failed to import ... row:', error);`，保留 warn 但只印 error 物件
- impl `src/services/cleanupTimezone.ts:36` — 現行 `console.log('[Cleanup] Updated timezone from ${setting.timeZone} to ${deviceTz}');`，使用者所在時區屬偏好設定
- impl `src/services/cleanupTimezone.ts:41` — 現行 `console.log('[Cleanup] No old timezone data found. All clean!');`
- impl `src/services/cleanupTimezone.ts:43` — 現行 `console.log('[Cleanup] ✅ Cleaned up ${updatedCount} timezone(s)');`
- impl `src/services/cleanupInvalidIconIds.ts:72` — 現行 `console.log('[Cleanup] Reset ${healedAccounts} account / ${healedCategories} category invalid iconId(s) to defaults');`
- impl `src/services/cleanupScheduleStamps.ts:48` — 現行 `console.log('[Cleanup] Backfilled updated_on for ${unstamped.length} schedule(s)');`
- impl `src/utils/timeHelper.ts:42` 與 `:56` — 現行 `console.log('[timeHelper] Invalid timezone: ${timeZone}. Using fallback.');`，每次遇到無效時區都印、量可能很大
- impl `src/services/iapService.ts:58` — 現行 `console.log('IAP Service Initialized (Mock Mode)');`
- impl `src/services/iapService.ts:233` — 現行 `console.log('Mock purchasing ${sku}');`
- impl `src/services/devSeed.ts:467` — 現行 `console.log('[mockData] Recurring instances generated — transactions: ${recurTxCount}, transfers: ${recurTfCount}');`
- impl `src/components/UndoDebugConsole.tsx:81` — 現行 `console.log('Mock revert: ${type}');`

iapService 那兩條落在 `IS_MOCK_MODE` 分支，正式版執行期到不了，執行面風險低；但四條都沒有 `__DEV__`，字串照樣被 metro 打包進 release bundle。`__DEV__` 是編譯期常數、消得掉字串，`isProductionBuild` 是執行期讀原生模組、消不掉。devSeed 與 UndoDebugConsole 可另比照 `src/services/regressionFixture.ts:162` 在函式入口加 `isProductionBuild` 早退，與套閘不衝突。

### 該拿掉閘的

- 本次盤查零筆。55 條 QA marker 全數有閘、無漏網，也沒有把該留給正式版的錯誤記錄誤閘掉。
- 保留判準記錄下來供後續沿用：`console.error` 與 `console.warn` 若記的是真異常且不含使用者實際值，一律不套閘、正式版該留。已確認屬於這一類、不得動的有 `syncEngine.ts` 的 157、167、207、295、457，`userService.ts` 的 66、72、165、169、180、185、223、274，三支 cleanup 各自的 console.error，`AuthContext.tsx` 的兩條 Data-erase console.error，以及 `adapter.native.ts` 的 `onSetUpError`。
- 後端一律不套閘，`__DEV__` 在 Cloud Functions 不存在。
- 一次性驗證方式：改完跑一次全 `src` 掃描，列出所有不在 `__DEV__` 區塊內的 `console.log`，人工逐條判斷是否含使用者資料。這件事目前沒有機械閘，建議收進 check_plan 之外的獨立 lint 規則，屬後續主題、不在本包。

---

## 測試修正清單

### 假綠與零覆蓋

- impl 新增 `src/services/recurringLogic.forwardPaths.test.ts`。`createSchedule`、`updateSchedule`、`deleteSchedule`、`getScheduleInstancesFrom` 四支正向函式全 repo 零測試呼叫，而 R00 序 7 把六條 RC-04 與 RC-05 檢查點掛在 `recurringLogic*.test.ts` 上。沿用 `recurringLogic.restoreScheduleInstances.test.ts` 第 27 至 33 行那組 database mock，`write` 直接跑、`batch` 收 ops 並套 mutator，不要像 `convertToSchedule.test.ts` 那樣把 `recurringLogic` 自身的相依全 mock 掉。三個 describe：`createSchedule` 斷言排程本體與首筆實例在同一次 batch 落庫；`updateSchedule` 分 ONLY_THIS 與 FUTURE 兩路，ONLY_THIS 斷言 batch 內無排程本體的 op，FUTURE 斷言原排程 `endOn` 被截到前一週期且新排程被建；`deleteSchedule` FUTURE 斷言 `endOn` 截斷與軟刪筆數。
- impl `src/services/transferLogic.test.ts` 補一個 describe 覆蓋 `deleteTransfer`。該檔 import 只有 `createTransfer` 與 `updateTransfer`，13 個 it 全在匯率補錄路徑上，而 R00 序 6 宣稱 RC-03 刪除為軟刪除且不刪已產生的匯率記錄已收。既有的 database mock 已足夠：第一條斷言該 transfer 列的 `deletedOn` 被寫成正整數時間戳、且 mock 未收到任何 destroy 或 markAsDeleted；第二條先跑一次跨幣別 `createTransfer` 讓正反兩筆 `currency_rates` 落進 mock store，再 `deleteTransfer`，斷言 store 內 `currency_rates` 的筆數與內容一列未動。復原半邊若由 UndoContext 承載，序 6 的引句要同步拆句或補列對應檔。
- impl `src/services/localDbService.test.ts:214` 的 `searchTransactions` 那個 it 標題承諾 newest-first，body 零排序斷言、`take` 也不驗 50。改寫成涵蓋兩張表的 `it.each`，同時收 `searchTransfers`。三段斷言：抄同檔第 190 至 196 行 `getLatest*` 那組現成寫法，斷言 `sort.sortColumn` 為 `date`、`sort.sortOrder` 為 `desc`；取 take clause 斷言筆數為 50，欄位名先印一次確認；保留既有的 `findSqlClause` 斷言。標題同步改成兩張表都涵蓋。
- impl `src/services/localDbService.test.ts` 的 `findWhere` 只比對 type 與 left、不看 comparison。`notDeleted()` 改成 `Q.notEq(null)` 語意完全反轉、軟刪列全回清單，五個站點一條都不會紅。加一支 `expectExcludesDeleted(clauses)`，取出該 clause 後斷言 `comparison.operator` 為 `eq` 且 `comparison.right.value` 為 `null`，把第 85、100、136、152、186 行五處全換掉。`disabled_on` 的第 86、101 行同型、一併換。同一行上方的 `user_id` 斷言本來就有驗 `comparison.right.value`，落差是可見的。
- impl `src/contexts/PremiumContext.storeKit.test.tsx` 補首次解析完成前的斷言。全檔 `isPremiumLoaded` 只有三處、全是 `toBe(true)` 且都在 `await flush()` 之後，PM-05 前半句那個視窗零斷言。把現有 render 的 `await flush()` 抽成參數做出不 flush 的變體，搭配 deferred promise：`mockGetAvailablePurchases.mockImplementation(() => new Promise(res => { release = res }))`。render 後立刻讀 latest，斷言 `isPremiumLoaded` 為 false 且 `currentTier` 未被當成有效判準；再 release 加 `await flush`，斷言轉 true。`PREMIUM_LOAD_FALLBACK_MS` 為 10000，同步視窗內不會觸發保底逾時，用真 timer 即可。
- impl `src/services/exportService.test.ts` 補 header describe，收 AS-06 的欄序、UTC 偏移、儲存精度三件事，目前三者皆無斷言。用同檔第 49 至 52 行現成的 `getWrittenCsv()` 取輸出。欄序：`templateService.ts` 第 10 行與第 21 行的 header 目前是函式內的區域 const，先抽成 exported 常數 `TRANSACTION_TEMPLATE_HEADER` 與 `TRANSFER_TEMPLATE_HEADER`，`exportService` 與測試同時引用，再斷言 csv 第一行逐字等於該常數。UTC 偏移：種一筆已知毫秒 date 的交易，斷言 datetime 欄符合 `/[+-]\d{2}:\d{2}$|Z$/`，且以 `importService` 的 `parseDate` 反解回同一絕對時間。儲存精度：斷言 amount 欄等於落庫的縮放整數而非顯示值。本條與現有的不輸出 id 欄 describe 語意相鄰，合併成同一個 header describe、不另起。
- impl `src/services/regressionFixture.test.ts` 誠實化。describe 名為 fixture 常數表對帳 no1_fixtures.md、docblock 寫改 fixture 表時本檔會紅，但整支沒有任何 `readFileSync`。不要改成跨 repo 讀檔：impl 有 worktree 慣例，從 impl 相對路徑推 quality git 在主 git 成立、在 worktree 內整條斷掉，寫成 skip 又等於沒驗。改法是把 describe 名改成 seeder 常數金牌值鎖定，docblock 拿掉那句、改成本檔鎖 seeder 側；md 側對帳為手工，見 quality git 索引。日後真要機械化，正確落點是 quality 側 check_plan 加一項去讀 impl 的 `regressionFixture.ts`，該方向的路徑推導 check_plan 第 214 至 231 行已經有。

### R00 核對列對應強度加強

以下全在 quality `no3_run_scripts/no2_r00_static_verification.csv`。

- 序 7 的動作欄把 `recurringLogic*.test.ts` 這個 glob 換成逐檔列出五支，讓 check_plan 第 6 項對刪檔有反應。
- 序 9 的 HD-04 兩半都不在該列所列的檔案裡。第一條斷言類別分組依金額由大到小，日期分組依日期由新到舊，實作在 `PeriodDataStore.ts` 第 551 行與第 574 行，但 `PeriodDataStore.test.ts` 五個 describe、14 個 it 全在快取鍵、user scope、停用排除與訂閱上，零排序斷言。加強方式：impl 側在 `PeriodDataStore.test.ts` 補一個 describe，沿用同檔既有 seed 手法種跨日期與跨類別的交易，分別在 `groupMode` 為 date 與 category 下斷言回傳 sections 的 id 順序。第二條斷言轉帳依已選帳戶分側，有紮實斷言，但在 `transferDisplayLogic.test.ts`、該檔列在序 8 不在序 9，csv 側在序 9 動作欄補上該檔路徑；不要把引句搬去序 8，序 8 的 CU-05 引句用字不同，搬過去會讓 check_plan 第 3 項的逐字反向對帳失配。
- 序 9 的 HD-02 斷言非法持久值回退預設 day 與 category，讀取失敗不寫回，兩半都不在被指名的 `homeFilterPersistence.test.ts` 裡，該檔 11 個 it 只驗三支純函式對集外值與壞 JSON 回 null。加強方式：impl 側在 `HomeFilterContext.selectionPersist.test.tsx` 加第二個 describe，該檔的 provider mock 基建現成。第一條 settings row 帶集外的 `homeTimeGranularity` 與 `homeGroupMode`，斷言 hydrate 後 context 的 `timeGranularity` 為 day、`groupBy` 為 category。第二條讓 settings 讀取 reject，斷言 context 停在預設值且假 DB 的 update 一次都沒被呼叫。csv 側序 9 動作欄補上該檔路徑。
- 序 5 的 LD-02 毫秒引句在序 5 五支檔內都無對應，那些 `1700000000000` 全是 mock 的 `getCurrentTimestamp` 回傳值與 cascade 同戳記斷言。真證據在序 4 的 `realDb.spike.test.ts`，它以真 LokiJS 引擎讀回 `_raw.date`。加強方式：把該引句自序 5 已驗欄剪下、貼進序 4，序 5 保留其餘八條；引句字串未改，check_plan 第 3 項不受影響。另在 `realDb.spike` 補一條逐表掃 `created_at`、`updated_on`、`deleted_on` 讀回皆為毫秒級的斷言，讓 `SoftDeletableModel.ts` 這個實作錨真的被執行到。
- 序 4 動作欄列的 `AuthContext.*.test.tsx` 展開七支、加 `pickDistinctIcons.test.ts` 一支，共八支不承載該列任何一條檢查點。刪掉這兩條樣式，只留 `schema.test.ts`、`realDb.spike.test.ts`、`preferenceNormalize.test.ts` 三支逐檔列出。AuthContext 那批守的是 bootstrap 與帳號生命週期，要收檢查點應另立一列對應 AU-02 與 AU-03。
- 序 2 預期欄寫全數綠燈、無 failed 或 skipped，與實跑矛盾：實跑是 1 skipped、846 passed。那一筆是 `__tests__/App.test.tsx:39` 的 `test.skip`、屬刻意保留的意圖佔位。預期欄改成全數綠燈、failed 為 0、skipped 恰為 1，該筆為 App.test.tsx 的 native mock harness 佔位，把已知數字寫死。
- 序 6 說明欄寫 quotaService 本身邏輯無測試檔，已過時，`quotaService.test.ts` 已存在、15 個 it、序 12 就指名引用它。改成對應手動場次 R03；配額累加此處為 syncEngine 呼叫端斷言，quotaService 自身邏輯由序 12 的 quotaService.test.ts 收下。同一批補齊的另四支對應列一併掃過。
- quality `no3_run_scripts/no2_r00_static_verification.md:21` 末句仍寫九條斷言在 impl 無對應測試檔，列於索引的覆蓋例外表，與索引現況無例外、212 條全數被收下直接打架。改成原九條無對應測試檔的斷言已於 2026-08-07 補齊並收進本場核對列，覆蓋例外表現為空。

---

## 工具強化

### check_plan.sh 新增檢核

以下全在 quality `no2_qa_tools/check_plan.sh`。

- 第 5 項抽取修正。第 117 行的 impl 側抽取改成只認真的 console 呼叫，判準是命名空間必須出現在 `console.<方法>` 的引數位置，而非註解或字串。改後為 `grep -rhoE 'console\.[a-z]+\([^)]*QA [A-Z]+' "$impl/src" --include=*.ts --include=*.tsx | grep -oE 'QA [A-Z]+'`。順帶消掉能力側寫第 77 行自承的 `QA A` 誤命中，也讓 `QA FINDING` 這種註解殘留不再被判過。
- 第 6 項 glob 強度。現行對每條樣式只判命中數是否為 0，41 條樣式中有八條是 glob、合計展開 31 支檔，刪掉其中 23 支這一項仍全綠。兩條路擇一：csv 側改逐檔列出、不用 glob，41 條樣式展開後共 64 支檔、一次性成本可接受；或保留 glob 但把每條樣式的命中數與一份版控基線清單比對，少於基線即失配，基線檔放 `no2_qa_tools/` 下、與 csv 同批更新。不要留現在這個刪 23 支檔零訊號的狀態。
- 新增第 8 項值域與跨層一致。四個子判，全部純文字比對、無外部相依：csv 第七欄手段值必須是能力側寫手段表 id 集合的子集；第三欄類型只准四值；第六欄驗證者只准兩值；每條已驗引句在分冊對應檢查點的手段欄與該 csv 列手段欄相同，且分冊檢查點的驗證者與手段表執行者欄相符。手段表抽取要以 `/^## 手段表/` 起段、`/^---/` 收段，避免抽到就緒探測表。兩份清單比對一律 `grep -vxF`、不用 comm。
- 新增第 9 項受阻手段零出現。手段表狀態欄為受阻的 id 一旦出現在任何 csv 即 fail。現況只有 `callable-api`。
- 第 8 項的第四子判在資料未修前必然報 10 筆，那是它該有的第一個訊號、不是誤報。動工順序是先修資料再加閘：分冊 10 條 qa-markers 檢查點的驗證者由使用者改成 Claude，與能力側寫執行者欄及 csv 的 9 列對齊。
- 新增覆蓋例外表與散文一致的廉價子判，掛在第 1 項之後。以既有 `extract_exceptions` 取得例外表列數，為 0 時斷言全部場次 md 內不得出現帶數字提及覆蓋例外表的句子，非 0 時斷言 R00 md 必須提及該表。實作用 `grep -l` 掃 `no*_r*.md`，不解析散文語意。
- 中間檔改 mktemp。第 72 至 74、87 至 89、92 至 93、97 至 102、116 至 120 行共 19 處 `/tmp/cp_*.txt` 全改到 `run_checks` 開頭建立的暫存目錄下。理由是本專案慣例多 worktree 多 session 並行，兩支 check_plan 同時跑會互相覆寫、兩邊都拿到混合結果且看起來正常。selftest 分支第 167 至 168 行已有自己的 mktemp 與 trap，兩個 trap 會互相覆蓋，要併成同一個變數、只留一個 trap。
- 第 92 至 93 行的失配明細用 `comm -23` 與 `comm -13`，違反本專案比對兩份清單用 `grep -vxF`、不用 comm 的規則，且它出現在唯一會被人逐條讀的失敗分支上。改成 `grep -vxF -f` 兩式，輸出語意不變。同檔第 87 行與第 97 行用的正是 `grep -vxF`。

### check_plan.sh selftest 要加的壞資料

- 現行 fixture 同時觸發四項失配，門檻卻寫 `-ge 3`，note 文案也只列三項、漏了反向那項。改成集合比對而非單一數字：`fail()` 除了累加計數外，把當前項次編號 push 進陣列，`run_checks` 內以變數標記當前項次；selftest 斷言該集合恰等於預期集合。現在數量對得上但抓錯項的情況偵測不到。
- 第 6 項與第 7 項目前完全沒有自驗。selftest 的暫存目錄只造 `no2_r00_x.csv` 與 `no1_x.md`，第 6 項因為找不到硬編檔名而略過，第 7 項的 glob `no*_r*.md` 一次都沒匹配就判過。加兩塊 fixture：把 `no2_r00_x.csv` 改名為 `no2_r00_static_verification.csv`，內容加一條指向 `src/nope/ghost.test.ts` 的路徑，預期第 6 項咬到零命中，假 impl 已在第 199 行建好可直接沿用；另造一支 `no9_r99_x.md` 寫前置場次指向不存在的 R98，預期第 7 項咬到找不到對應檔。
- 第 8 項與第 9 項的壞資料：一列手段寫 `callable-api`、一列手段拼成 `qa-marker`、一列類型寫成不在四值內的值、一列分冊檢查點驗證者與手段表執行者不符。
- 覆蓋例外表一致子判的壞資料：例外表為空但場次 md 散文寫九條列於覆蓋例外表。
- 全部加完後預期集合為第 2、3、4、5、6、7、8、9 項各至少一筆。

### query_local_db.sh 新增不變式

以下全在 quality `no2_qa_tools/query_local_db.sh` 的 `cmd_assert`。所有查詢一律排掉 `_status='deleted'` 的列，那是 WatermelonDB 待同步的刪除標記，raw dump 撈得到但 app 眼裡已不存在。

金額不變式擴到全部六個縮放整數欄。現行只查 `transactions.amount`，`transfers.amount_from`、`amount_to`、`schedules.template_amount`、`template_amount_from`、`template_amount_to` 全在外，而跨幣別轉帳與排程樣板正是最容易在倍率上出錯的兩條路徑。改成從 `sqlite_master` 逐表、以 `pragma_table_info` 逐欄推導：

```sql
SELECT m.name AS tbl, p.name AS col
FROM sqlite_master m JOIN pragma_table_info(m.name) p
WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite\_%' ESCAPE '\'
  AND (p.name = 'amount'
    OR p.name LIKE 'amount\_%' ESCAPE '\'
    OR p.name LIKE 'template\_amount%' ESCAPE '\');
```

逐欄違例查詢，同時印樣本數，空表不等於通過：

```sql
SELECT COUNT(*) FROM "<tbl>"
WHERE "<col>" IS NOT NULL AND CAST("<col>" AS INTEGER) != "<col>";
```

不要加金額上界判準。`MAX_STORAGE_AMOUNT` 就是 `Number.MAX_SAFE_INTEGER`，對 REAL 欄近乎恆真；且這支 shell 沒有 `--impl` 也讀不到 TS 常數，真要判上界得先加參數與解析器，成本遠高於收益。

時間毫秒不變式擴到全部時間欄。現行只查 `created_at`，`date`、`updated_on`、`deleted_on`、`disabled_on`、`last_synced_at`、`last_login_at`、`start_on`、`end_on`、`schedule_instance_date` 九個全在外，而交易的 `date` 才是使用者看得到、也最容易在匯入路徑上出錯的那一欄。欄位推導：

```sql
SELECT m.name AS tbl, p.name AS col
FROM sqlite_master m JOIN pragma_table_info(m.name) p
WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite\_%' ESCAPE '\'
  AND (p.name LIKE '%\_at' ESCAPE '\'
    OR p.name LIKE '%\_on' ESCAPE '\'
    OR p.name = 'date'
    OR p.name LIKE '%\_date' ESCAPE '\');
```

逐欄違例查詢，帶 OBS-03 佔位哨兵白名單。`currency_rates.date` 的佔位值為 1，取 1 不取 0 是因為 WatermelonDB 的 `@date` setter 吞 falsy，不白名單會穩定誤報一筆：

```sql
SELECT COUNT(*) FROM "<tbl>"
WHERE "<col>" IS NOT NULL AND "<col>" > 0 AND "<col>" < 1000000000000
  AND NOT ('<tbl>' = 'currency_rates' AND '<col>' = 'date' AND "<col>" = 1);
```

新增裝置 schema 版本不變式，對應 LD-01。LD-01 三條 jest 檢查點全在宣告面，`schema.test.ts` 那條斷言最高 migration 版本等於 schema 版本，比的是兩份原始碼、不是這台裝置上那個 db 檔。migration 半途失敗、裝置卡在舊版本時三條照樣綠。先給腳本加 `--impl` 參數，以 `grep -m1 'version:'` 取宣告值；沒帶 `--impl` 時退成只印裝置版本、標記未比對，不要靜默略過：

```sql
PRAGMA user_version;
```

新增串聯軟刪完整性，對應 EN-04。jest 側驗的是 batch 裡收了哪些 prepareUpdate，驗不到庫裡最後長什麼樣；batch 部分失敗或 undo 回滾留半套，殘留只有直查看得到：

```sql
SELECT COUNT(*) FROM transactions t
JOIN accounts a ON a.id = t.account_id
WHERE t._status != 'deleted' AND t.deleted_on IS NULL
  AND a._status != 'deleted' AND a.deleted_on IS NOT NULL;

SELECT COUNT(*) FROM transactions t
JOIN categories c ON c.id = t.category_id
WHERE t._status != 'deleted' AND t.deleted_on IS NULL
  AND c._status != 'deleted' AND c.deleted_on IS NOT NULL;

SELECT COUNT(*) FROM transfers f
JOIN accounts a ON a.id IN (f.account_from_id, f.account_to_id)
WHERE f._status != 'deleted' AND f.deleted_on IS NULL
  AND a._status != 'deleted' AND a.deleted_on IS NOT NULL;
```

新增孤兒外鍵。匯入不沿用來源 id、merge 移轉、AS-07 硬刪三條路徑都可能造孤兒，現在沒有任何一層在看。五組各掃一次，此處列兩組作範式：

```sql
SELECT COUNT(*) FROM transactions t
WHERE t._status != 'deleted' AND t.account_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM accounts a WHERE a.id = t.account_id AND a._status != 'deleted'
  );

SELECT COUNT(*) FROM transactions t
WHERE t._status != 'deleted' AND t.schedule_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM schedules s WHERE s.id = t.schedule_id AND s._status != 'deleted'
  );
```

新增跨身分汙染。現行第四項只驗 `user_id` 非空，真正的多租戶風險是引用跨身分。本機庫刻意不在登出時清空、多身分共存是常態，這是 AS-07 與多身分共存唯一能自動化的把關：

```sql
SELECT COUNT(*) FROM transactions t
JOIN accounts a ON a.id = t.account_id
WHERE t._status != 'deleted' AND a._status != 'deleted' AND t.user_id != a.user_id;

SELECT COUNT(*) FROM transactions t
JOIN categories c ON c.id = t.category_id
WHERE t._status != 'deleted' AND c._status != 'deleted' AND t.user_id != c.user_id;

SELECT COUNT(*) FROM transfers f
JOIN accounts a ON a.id IN (f.account_from_id, f.account_to_id)
WHERE f._status != 'deleted' AND a._status != 'deleted' AND f.user_id != a.user_id;
```

新增 RC-06 實例唯一。`recurringLogic.test` 驗的是 in-flight lock 與 idempotent 重跑，其 seed helper 一律給 `deletedOn: null`，已軟刪除實例視為已存在不重生那半根本沒造出樣本。刻意不排除軟刪列、只排 `_status='deleted'`，兩張表各掃一次：

```sql
SELECT COUNT(*) FROM (
  SELECT schedule_id, schedule_instance_date, COUNT(*) AS c
  FROM transactions
  WHERE _status != 'deleted' AND schedule_id IS NOT NULL AND schedule_instance_date IS NOT NULL
  GROUP BY schedule_id, schedule_instance_date
  HAVING c > 1
);
```

新增 RC-01 金額正負號。jest 驗的是 `normalizeTransactionAmount` 純函式，匯入與合併繞過它直接寫值時不會紅：

```sql
SELECT COUNT(*) FROM transactions t
JOIN categories c ON c.id = t.category_id
WHERE t._status != 'deleted' AND t.deleted_on IS NULL
  AND ((c.type = 'expense' AND t.amount >= 0) OR (c.type = 'income' AND t.amount <= 0));
```

零金額是否合法要先向 spec 確認。若允許零，把 `>=` 與 `<=` 改成 `>` 與 `<`，並在該行註解寫明依據。

新增 AS-04 settings 值域。髒值落庫後讀取層會靜默 normalize 掉，UI 永遠看不出來：

```sql
SELECT COUNT(*) FROM settings
WHERE _status != 'deleted'
  AND (week_start IS NOT NULL AND week_start NOT IN ('auto', 'sunday', 'monday')
    OR launch_mode NOT IN ('home', 'expense', 'income', 'transfer')
    OR theme IS NULL OR theme = '');

SELECT COUNT(*) FROM (
  SELECT user_id, COUNT(*) AS c FROM settings
  WHERE _status != 'deleted' GROUP BY user_id HAVING c > 1
);
```

值域清單與 impl 常數同源，`calendarGrid.ts:11` 與 `preferenceNormalize.ts:21`，但 shell 讀不到 TS、只能在腳本內寫一份。寫的同時在該行註解標出這兩個來源檔行號，並在 impl 側加一支 guard test 鎖住常數不漂，不要只靠註解。

### query_local_db.sh selftest 要加的壞資料

- 現行 selftest 只餵 `cmd_assert` 一個現成 db 檔，完全繞過三塊：`snapshot()` 的 WAL 快照設計、`sql` 子指令的首動詞白名單與唯讀模式雙道守門、`cmd_tables` 的存活與軟刪分欄邏輯。
- WAL 段：用 sqlite3 開 WAL 模式寫一筆後不 checkpoint，直接對原檔跑 `snapshot` 再讀，斷言讀得到 WAL 裡那筆值；同時對照直接以 immutable 讀原檔讀不到，兩相比才證明得了 snapshot 的價值。
- 白名單段：對 `DELETE FROM x`、`SELECT 1; DELETE FROM x`、開頭帶空白的 `select 1` 三種輸入分別斷言拒絕於首動詞、被唯讀模式拒絕、放行。第二種要真的走到 sqlite 才驗得到第二道門。
- tables 段：對壞 db 加一筆 `_status='deleted'` 的列，斷言該列計入總列數但不計入存活。
- 新增的每一條不變式都各造一筆違例列：帶小數的 `amount_from`、秒級的 `date`、`user_version` 與宣告版本不符、串聯半套、孤兒外鍵、跨身分引用、同排程同日期兩筆、支出金額為正、`week_start` 集外值。
- selftest 現行只呼叫 `cmd_assert`，要改成逐段呼叫，門檻改成集合比對而非單一數字。

### 新增不變式的落位前提

新增的落庫不變式若要被場次收下，必須先動計劃層、再動腳本層，順序不能顛倒，否則 csv 的手段欄會與分冊檢查點宣告的手段互相矛盾。目前 `sqlite-local` 在分冊與 csv 皆零出現。四步：

- 在 `~/.claude/skills/test_plan_writer/run_script_format.md` 第 70 至 75 行的 Claude 節點落位分流補第三類。`sqlite-local` 屬狀態相依但只讀快照，必須排在該步寫入完成之後、不與 UI 操作同列。現行分流只列了狀態相依內嵌的 firestore-read、cloud-logging、qa-markers，與零依賴集中 R00 的 jest-app、jest-backend，`sqlite-local` 兩邊都不屬於。
- 在 `no2_regression_plan/` 對應分冊新增檢查點，層寫落庫、手段寫 `sqlite-local`，斷言講真機庫裡的形狀而非函式行為。不要改寫既有那幾條 jest-app 的檢查點。
- 在對應場次 csv 插 Claude 節點列跑查詢器，已驗欄逐字抄新增的斷言。
- 跑 check_plan 確認正向、反向、計數三項仍全綠。覆蓋例外表現況已清空，新增斷言若沒被收下會立刻在正向那項爆。

---

## 原生機制改動

### hook 誤擋的修法

`~/.claude/hooks/lib/guards/redirect.sh` 第 27 行把命令裡任何一個 `>` 字元當寫檔訊號，硬擋唯讀指令。實測被擋的第一例正是 run_script_format 的對帳配方本身，`awk 'FNR>1'` 與 `grep '=>'` 都 exit 2。改成語法位置判定、不是字串出現判定：`>` 這一支換成重導向運算子後緊接第一個 token 的形式，前一字元為 `-`、`=`、`<` 時排除，用以擋掉箭頭與比較運算子。tee 與四支 PowerShell cmdlet 那幾支維持原樣、本來就已經是 token 形。

```sh
# redirect.sh:27 的 `>` 那一支改成
'(^|[[:space:]])([12]?>>?|tee[[:space:]]+(-a[[:space:]]+)?)[[:space:]]*["'"'"']?(/[^[:space:]"'"'"']*/ai-company/product/[^/]+/no[34567]_)'
```

`~/.claude/hooks/lib/common.sh:112` 把 CR 與 LF 壓成空白，多行命令與 heredoc 內文因此併成同一段、更容易命中，這條在改完正則後風險降低，暫不動。

測試側目前只有 should-block 案例、沒有任何 should-pass 案例。把 `awk 'FNR>1' <主 git csv>` 與 `grep 'x -> y' <主 git ts>` 兩條當 expect 0 加進 `~/.claude/hooks/tests/windows-enforcement-test.sh` 的對應段，否則下次調正則會再破。

### hook 漏擋的修法

同一支 redirect guard 宣稱在補 worktree-only 的繞道，寫檔訊號卻只列 `>`、`tee `、四支 PowerShell cmdlet。`cp`、`mv`、`sed -i` 寫進主 git 的 `no[34567]_` 全部靜默放行。守與擋剛好對調。與誤擋一次改完，在路徑比對之後補三類目標抽取：

- `cp`、`mv`、`install`、`patch` 取該命令段最後一個位置參數當目標，命中主 git `no[34567]_` 即 exit 2。
- `sed` 只在帶 `-i` 時檢查其後全部檔案參數，命中即 exit 2。
- `python3 -c` 與 `node -e` 走保守偵測，內文同時出現主 git `no[34567]_` 路徑與 `'w'` 或 `writeFile` 時回 `permissionDecision: ask`、不硬擋，避免誤殺唯讀腳本。

三類各補一條 expect 2 案例進 `windows-enforcement-test.sh`。

### verification-report 範圍收斂

`~/.claude/hooks/lib/guards/verification-report.sh:23` 的 case pattern 只看副檔名不看 module，後端 module 的路徑逐字命中，於是改一支 Cloud Functions handler 會被索討 design canvas port 或 Metro port，以及使用者打開後該看到的差異，後端沒有可預覽畫面、這兩項填不出來也不該填。同一 pattern 也命中純服務層。

- 在該檔第 20 行的 case 開頭加一條 `*/no3_cloud_functions/*|*/functions/src/*) return 0 ;;` 明確排除後端。
- 第 23 行與第 27 行的 worktree impl 對應支收斂成與 design guard 同一組路徑：`*/src/screens/*.tsx`、`*/src/components/*.tsx`、`*/src/constants/theme.ts`。
- 兩支 guard 對什麼算 UI 既然必須一致，把判定抽成 `lib/common.sh` 的 `hook_is_ui_path` 供兩邊呼叫，避免下次只改一邊。`design-impl-alignment.sh:27` 目前只認 screens、components 與 theme 三處。
- `no4_product_designs` 那兩支維持現狀。

### multi-tier-sync 的後端場次點名與 fork 收斂

改後端 impl 永遠拿不到場次點名，映射表的 CF 列是死列，而後端正是付費與刪帳號那條鏈。兩道關卡各擋一半：

- `_mts_scene_hint` 以 `no6_product_quality/$module` 組 quality root，後端 module 是 `no3_cloud_functions`、該目錄不存在，直接返回。修法是在函式開頭加 module 別名對照，`no3_cloud_functions` 的回歸計劃寄在 `no2_accounting_app` 的 Quality git，quality git 的 CLAUDE.md 第 24 行已寫明這件事；quality root 解析先查別名再組路徑。
- rel 抽取恆為 `src/` 開頭，而映射表 CF 列的前綴欄寫的是帶散文的後端 impl 的 functions/src/ 這種形式，前綴比對永不成立。修法是 rel 抽取對後端改成從 `functions/src/` 起算；同時把 `no0_index.md` 路徑映射表 CF 列的前綴欄改成純路徑，散文移到表下的註。
- 改完在 `~/.claude/hooks/tests/impl-scene-hint-test.sh` 補一條後端案例，現有 19 條全綠、可直接當回歸網。

同一支檔違反自己第 101 至 105 行的禁 fork 規則，三刀依代價由低到高：

- 所有 `echo | grep -qE` 與 `echo | sed -E` 換成 `[[ =~ ]]` 加 `BASH_REMATCH`，第 144 行已是可照抄的樣板。
- 迴圈內 `basename "$pdir"` 換成 `${pdir##*/}`，`tr 'A-Z' 'a-z'` 換成 `${var,,}` 或直接用已開啟的 `nocasematch` 比對。
- `_mts_scene_hint` 比照 `_mts_jest_hint` 改成把結果放全域變數、去掉命令替換；函式內掃索引與掃 13 支 csv 的兩次 awk 合併成一次。

### capability-probe 噪音收斂與探測補齊

該 hook 自述只在有缺口時輸出、讓輸出恆為真警報，現況違反該句：掃描面收全部產品的 `package.json`，LiquidGlassHeaderTemplate 有 jest 依賴、無 node_modules、且整個產品沒有 Quality git，卻每次開 session 都被列成缺口。

- 掃描面收斂：在既有的檔案存在判斷之後加一道閘，由 `package.json` 反推同 module 的 `no6_product_quality/<module>/no1_capability_profile.md`，檔不在就 continue，讓沒有回歸計劃的 module 整組略過。
- 補三個零副作用探測，各包 `timeout 5`：`qa-markers` 探 `/tmp/sim-review-metro-*.log` 有檔且內含 `QA ` 前綴列；`sqlite-local` 跑查詢器的 `path` 子指令，該子指令只印路徑、不查資料；`firestore-read` 在既有的 `command -v firebase` 之後補 `firebase login:list` 抓有無有效帳號。就緒探測表列 7 個手段，probe 目前只覆蓋 jest 與 firebase 存在性兩項，缺的三項都是最脆的。
- 三者都會 spawn 進程，SessionStart 可接受但要守住 timeout、別掛住開場。

### main-on-clean-main 與 sim-review 的狀態互通

`~/.claude/hooks/main-on-clean-main-guard.sh` 掛在 Stop、每輪掃全部主 repo 的 HEAD，而回歸驗證模式的設計就是讓主 git 長時間離開 main、橫跨整輪約 7 小時。hook 自己在第 36 行寫明若 sim-review review 進行中、主 git 本該 detached、忽略本提醒即可，等於承認在該情境恆為假警報，卻仍每輪重播。一個每輪出現、每輪要被忽略的警報，會稀釋它在真正該叫的時候的效力。

- sim-review 在 checkout 目標 ref 或 detach 之後 `touch /tmp/sim-review-active-<主 git basename>`，還原步驟移除它。生命週期與既有的 `/tmp/sim-review-metro-*.log` 一致、不進任何 git。
- guard 算出 repo 相對位置之後、進 case 之前加一道判斷：該 repo 有對應 marker 就 continue，其他 repo 照舊列。
- 第 36 行那句忽略本提醒即可隨之刪掉。`/game-stop` 的自癒步驟也多一個判斷依據。

### 該新增的機制：伴跑狀態檔

回歸執行過程中該機制化而未機制化的第一件事。228 列、135 列掛檢查點、36 列 Claude 節點、合計約 7 小時且明訂單日走完，判定目前全活在對話裡；auto-compact、換 session、隔天續跑三種中斷都等於整場重跑。

- 職責邊界要先講清楚：真正的硬邊界是執行紀錄不入 Quality git，不是不落任何檔。現行三處措辭寫成後者，讀起來連落到 Quality git 以外都被禁。改 `~/.claude/skills/sim-review/SKILL.md` 第 332 行與第 345 行、`~/.claude/skills/test_plan_writer/SKILL.md` 第 13 行，統一成執行紀錄不入 Quality git、伴跑狀態落 `~/.claude/game/regression-runs/<product>-<YYYYMMDD>.tsv`、該檔不進任何產品 git 這個說法。
- 狀態檔格式：一列一步，欄位為場次、序、判定、時間戳、備註。tsv 而非 csv，避開已驗欄那種全形分號多值的切分問題。
- sim-review 伴跑段的五步補兩條動作：每列判定後 append 一行；啟動時先讀該檔，有同場次紀錄就印出已完成到第幾列並問要不要接續。
- 全域 CLAUDE.md 的 Compaction 復原規範第 2 步目前寫的是泛泛的列尚未驗證或尚未 review 的項目，沒有狀態檔可列。同步在該步補一句：檢查 `~/.claude/game/regression-runs/` 有無當日進行中的回歸狀態檔。

### 該新增的機制：伴跑語體模式

`~/.claude/hooks/brevity-refresh.sh` 每輪無條件注入一句一事、15 字上限，`brevity-meter.sh` 的觸發水位是超長句與短句佔比的組合。而 QA 陪跑的格式鐵律寫死操作指引不適用回報的 15 字短句壓縮，格式是粗體步標題加編號子動作、每個子動作一行完整句、預期獨立成行。一段合規的伴跑操作指引每行都是動詞加受詞加目標狀態、必然超 15 字。meter 確實跳過 code fence，但 QA 指定的操作段格式不是 code block、跳不掉，而且它會把粗體標記剝掉讓步標題也進量測。

- 給伴跑一個 session 級靜音旗標，不要讓 brevity 去認 QA 的細節。sim-review 啟動伴跑時 touch `${TMPDIR:-/tmp}/claude-qa-mode-<session_id>`，沿用 brevity 已在用的暫存目錄與 session id 命名慣例；review 結束的還原步驟移除它。
- `brevity-meter.sh` 在讀訊息之前見 marker 直接結束。
- `brevity-refresh.sh` 見 marker 時把注入的 base 換成 QA 語體那條。
- 兩支 hook 只需要知道當下處在哪個模式，不需要知道 QA 的格式細節。既有的環境變數 bypass 靠 export 設不到 hook 進程，不能當作解法。

### sim-review 的伴跑前提補強

`/sim-review R<場次>` 沒定義該從哪個目錄打，兩種自然打法各卡一邊，而歧義發生在 7 小時流程的第一分鐘。共用前置的環境收集段硬性要求 cwd 落在 worktree 根之下否則 exit 1；回歸驗證模式明說跳過該檢查、主 git 直接取當前 git 的主 checkout，卻沒有任何一句說 cwd 該在哪。從 Quality git 打，抓不到 `package.json` name、抓不到 xcworkspace、讀不到 Info.plist，依規則要停下；從 impl 主 git 打則沒有任何指示說怎麼找到 Quality git 的場次腳本。

- 在回歸驗證模式段的差異清單補一條硬性前提：伴跑一律從 app impl 主 checkout 打，Quality git 路徑由同 module 路徑置換推導，`no5_product_development` 換成 `no6_product_quality`；推導不到就停下報路徑、不猜。check_plan 第 229 行已有一模一樣的 sed 推導可照抄。
- 同段再補一行：場次號不等於檔號，定位用 `no*_r05_*` 這種 glob、不要假設檔名前綴。現況 R05 落在 `no7_`、R10 落在 `no12_`，且 `no11` 是已移除舊 R09 的空號、刻意不回收。

### allowlist 補齊

回歸手段對應的指令沒進 allowlist，12 個雲端節點與 sqlite 查詢逐次卡權限，而 7 小時流程裡使用者正拿著裝置在操作。在 `~/Doc/ai-company/.claude/settings.local.json` 補唯讀 scope：

- `Bash(firebase firestore:*)`
- `Bash(firebase login:list)`
- `Bash(sqlite3 *)`
- `Bash(pgrep *)`
- `Bash(bash no2_qa_tools/query_local_db.sh *)`
- `Bash(bash no2_qa_tools/check_plan.sh *)`

不要加 gcloud。能力側寫的 cloud-logging 環境前提逐字寫同 firestore-read，走的是 firebase CLI。順手清掉確定不會再命中的一次性項：兩筆寫死 pid 的 kill、兩筆 `/tmp` 測試腳本、兩筆一次性 cp、一行寫死路徑的 simctl screenshot。清單裡的 `bash -n ~/.claude/hooks/*-guard.sh` 幾筆不是垃圾，那些 wrapper 檔仍在。

### 既有機制重疊矛盾的收斂

- UI 路徑定義兩套：`verification-report.sh` 與 `design-impl-alignment.sh` 各認一組。收斂到 `lib/common.sh` 的 `hook_is_ui_path`。
- 驗證者欄三面矛盾：分冊 10 條 qa-markers 檢查點寫使用者、能力側寫執行者欄寫 Claude 且限制欄明寫不由使用者貼回、csv 9 列寫 Claude。以能力側寫為準，改分冊，並由 check_plan 新增的第 8 項第四子判持續把關。
- 覆蓋例外表兩面矛盾：索引寫現況無例外，R00 md 散文仍寫九條列於例外表。以索引為準，改散文，並由 check_plan 新增的一致子判把關。
- memory 索引指向已作廢的舊 QA 結構：`project_susugigi_manual_qa_plan.md` 描述的是上一代六份文件、1112 條 R-ID、32 場 1064 步與三支已不存在的工具，而 Quality git 的 CLAUDE.md 第 48 行明令不引用不沿用舊內容。新 session 讀 memory 會先被帶去死結構、再自己撞上禁令。重寫該條目本文，換成現行三層結構與兩支工具的定位，明寫舊結構已封存、無繼承關係、不得引用；MEMORY.md 那一列的一句話摘要同步改掉。舊結構的追溯價值另開一條標題帶已封存字樣的 reference 條目收，不要跟現行的混在同一條。

---

## 涉及哪些 git 與層

改動橫跨三個 git，加上一份不在 git 內的 memory。動工前置四步照走：先跑 decision_framework_router 答上游四問，再對每個要動的層 git 各自 `git worktree add` 建同名 feat branch。

### impl git 的 app module

路徑 `~/Doc/ai-company/product/susugigi/no5_product_development/no2_accounting_app`，層為 impl、module 為 `no2_accounting_app`。承載：

- MRK-01 加 MRK-02、MRK-03、MRK-08、MRK-09、MRK-10、MRK-11、MRK-12、MRK-14 的全部 marker 落點
- `__DEV__` 閘修正的全部 30 餘條
- 測試修正清單假綠與零覆蓋全部七項
- R00 加強所需的 impl 側新測試：`PeriodDataStore.test.ts` 排序 describe、`HomeFilterContext.selectionPersist.test.tsx` 第二個 describe、`realDb.spike.test.ts` 逐表時間欄斷言
- `templateService.ts` 的 header 常數 export
- query_local_db 新增值域不變式所需的 impl 側 guard test，鎖住 `calendarGrid.ts` 與 `preferenceNormalize.ts` 的常數不漂

### impl git 的後端 module

路徑 `~/Doc/ai-company/product/susugigi/no5_product_development/no3_cloud_functions`，層為 impl、module 為 `no3_cloud_functions`。承載 MRK-04、MRK-05、MRK-06、MRK-07 四條後端 log。與 app module 同名 feat branch、同 subject 加 body 的配對 commit。

### Quality git

路徑 `~/Doc/ai-company/product/susugigi/no6_product_quality/no2_accounting_app`，層為 quality。承載：

- `no1_capability_profile.md`：刪 `QA FINDING`、加 `QA RATE`、命名空間清單同步
- `no2_regression_plan/`：10 條 qa-markers 檢查點驗證者改 Claude；PM-04、CU-05、AS 匯入、HD-02、LD-01 各新增一條日誌層 qa-markers 檢查點；LD-01 至 LD-03 與 RC-01、RC-06、EN-04、AS-04 新增落庫層 sqlite-local 檢查點
- `no2_regression_plan/no0_index.md`：路徑映射表 CF 列前綴欄改純路徑
- `no3_run_scripts/no2_r00_static_verification.csv`：序 2 預期欄、序 4 動作欄、序 5 與序 4 的引句搬移、序 6 說明欄、序 7 glob 展開、序 9 動作欄補檔
- `no3_run_scripts/no2_r00_static_verification.md`：第 21 行覆蓋例外表散文
- `no3_run_scripts/` 各場次 csv：R01 序 3 之後、R04、R05 序 20 之後、R06 序 8 之後、R10 匯入段與序 8 之後、R12 各補 Claude 節點列
- `no2_qa_tools/check_plan.sh`：第 5 項抽取修正、第 6 項 glob 強度、新增第 8 與第 9 項、覆蓋例外表一致子判、mktemp、comm 換 `grep -vxF`、selftest 集合比對與新壞資料
- `no2_qa_tools/query_local_db.sh`：新增 `--impl` 參數、九類落庫不變式、selftest 三段補齊

### Claude 設定 repo

路徑 `~/.claude`，不屬任何產品層。承載：

- `hooks/lib/guards/redirect.sh`：誤擋修法與漏擋補齊
- `hooks/lib/guards/verification-report.sh` 與 `hooks/lib/guards/design-impl-alignment.sh` 加 `hooks/lib/common.sh`：UI 路徑判定抽共用
- `hooks/lib/guards/multi-tier-sync.sh`：後端 module 別名、rel 抽取、三刀 fork 收斂
- `hooks/capability-probe.sh`：掃描面收斂與三個探測補齊
- `hooks/main-on-clean-main-guard.sh`：sim-review marker 判斷
- `hooks/brevity-refresh.sh` 與 `hooks/brevity-meter.sh`：QA 模式旗標
- `hooks/tests/windows-enforcement-test.sh` 與 `hooks/tests/impl-scene-hint-test.sh`：新增 should-pass 與後端案例
- `skills/sim-review/SKILL.md`：措辭改成不入 Quality git、狀態檔兩條動作、QA 模式旗標建立與移除、sim-review-active marker、伴跑 cwd 前提與場次號 glob
- `skills/test_plan_writer/SKILL.md` 與 `skills/test_plan_writer/run_script_format.md`：措辭同步、Claude 節點落位分流補 sqlite-local 第三類
- `CLAUDE.md`：Compaction 復原規範第 2 步補回歸狀態檔
- 這一批屬 self-modification，動工前先切 acceptEdits，commit 加 `self-modification` 標籤，且必須走正式 plan mode

### 不在 git 內

- `~/Doc/ai-company/.claude/settings.local.json` 的 allowlist 補齊與一次性項清理
- memory `project_susugigi_manual_qa_plan.md` 本文重寫與 MEMORY.md 索引列改寫，另開已封存條目

### 施工順序與 branch

四包順序有相依，建議拆成四個主題、逐一走完 review 加 commit 加 merge 再開下一個。

- 第一包 `feat/qa-hook-unblock`：只動設定 repo 的 redirect guard 誤擋與漏擋、加測試案例。必須最先做，否則後面每一包的對帳配方都被擋。
- 第二包 `feat/qa-marker-backfill`：impl 兩個 module 的 marker 與 `__DEV__` 閘，加 Quality git 的能力側寫命名空間、新增檢查點、場次 csv 補列。三個 git 同名 branch、配對 commit。
- 第三包 `feat/qa-assertion-hardening`：impl 的測試補齊、Quality git 的 R00 核對列加強與兩支工具強化。兩個 git 同名 branch。
- 第四包 `feat/qa-mechanism-hygiene`：設定 repo 的其餘 hook 與 skill 改動、伴跑狀態檔、allowlist、memory 重寫。走正式 plan mode 與 acceptEdits。
