//+------------------------------------------------------------------+
//|                                                       Panbes.mq5 |
//|                    CLCC + Auto Layering + Reentry                |
//|  Asisten cutloss & layering. Bukan EA sinyal.                    |
//|  Trader pasang 1 pending pertama (manual / HP); EA mengurus      |
//|  sisa layer, CLCC, reentry, dan visual bantu.                    |
//+------------------------------------------------------------------+
#property copyright "Panbes"
#property version   "1.00"
#property description "Panbes — CLCC + Auto Layering + Reentry"
#property description "Pasang 1 pending manual dengan comment [Grup][N][Pos]/[TF]/[CL]"
#property description "Contoh: A31/M1/4526.25"
#property description "Strategy Tester: wajib mode Every Tick"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| KNOWN LIMITATION                                                 |
//| Reentry counter tidak tertanam di comment order. Setelah restart |
//| VPS, counter di-reset ke 0 (spec v1). Enhancement: hitung ulang  |
//| event TP historis via HistorySelect() di OnInit — belum di v1.   |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
const long     InpMagic              = 0;        // disembunyikan; 0 = sama seperti order manual
const int      InpDeviation          = 30;
const int      InpMaxReentry         = 3;
const int      InpLayerBufferPoints  = 10;
const int      InpTpWindowMs         = 1000;

input group "=== Notifikasi ==="
input bool     InpAlertOnCL          = false;    // Alert saat CLCC
input bool     InpAlertOnReentry     = false;    // Alert saat reentry
input bool     InpAlertOnLayer       = false;    // Alert saat auto-layer
input bool     InpPushNotify         = true;     // Push notification ke HP (MetaQuotes ID)

input group "=== Mode Test (Strategy Tester) ==="
input bool            InpTestMode        = false;                  // Simulasi entry manual
input double          InpTestEntryPrice  = 0.0;                    // Harga entry order test
input double          InpTestTP          = 0.0;                    // TP order test
input double          InpTestSL          = 0.0;                    // SL order test
input double          InpTestLot         = 0.01;                   // Lot order test
input string          InpTestComment     = "A31/M1/4526.25";       // Comment order test
input ENUM_ORDER_TYPE InpTestOrderType   = ORDER_TYPE_BUY_LIMIT;   // Tipe order test
input datetime        InpTestDateTime    = D'2026.08.01 00:00:00'; // Waktu pasang (server)

//+------------------------------------------------------------------+
//| STRUCTS                                                          |
//+------------------------------------------------------------------+
struct PacComment
{
   string          groupCode;
   int             layerCount;
   int             position;
   ENUM_TIMEFRAMES timeframe;
   double          clPrice;
   string          tfText;
   string          clText;
};

struct LiveItem
{
   ulong           ticket;
   ulong           positionId;
   bool            isPosition;
   string          comment;
   PacComment      pac;
   bool            parsed;
   bool            ignored;
   double          price;
   double          sl;
   double          tp;
   double          lot;
   ENUM_ORDER_TYPE orderType;
   datetime        setupTime;
};

struct PacGroup
{
   string          groupCode;
   ENUM_TIMEFRAMES timeframe;
   double          clPrice;
   string          tfText;
   string          clText;
   string          pos1Comment;
   int             layerCount;
   int             direction;          // +1 BUY, -1 SELL
   datetime        lastCheckedBarTime;
   int             reentryCount;
   bool            layeringAttempted;
   bool            clExecuted;
   datetime        startedAt;
   double          pos1LastTp;
   bool            pos1TpReady;
   bool            orderNotified;
};

struct Snapshot
{
   ulong           positionId;
   ulong           ticket;
   string          comment;
   double          entry;
   double          sl;
   double          tp;
   double          lot;
   bool            isBuy;
};

struct TpSlot
{
   string          comment;
   double          entry;
   double          sl;
   double          tp;
   double          lot;
   bool            isBuy;
};

struct TpBatch
{
   string          groupCode;
   ulong           windowStartMs;
   TpSlot          slots[];
};

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade    g_trade;
PacGroup  g_groups[];
Snapshot  g_snaps[];
TpBatch   g_tpBatches[];
ulong     g_processedDeals[];
ulong     g_parseAlerted[];
ulong     g_ambiguousAlerted[];

bool      g_inRefresh        = false;
bool      g_testOrderPlaced  = false;
bool      g_syncingTp        = false;
bool      g_initScanDone     = false;
string    g_clccGroup        = "";

const string PREFIX_CL     = "CLLine_";
const string PREFIX_CLTEXT = "CLText_";
const string PREFIX_CD     = "CD_";
const string PREFIX_CD_OLD = "CountdownLabel_";

//+------------------------------------------------------------------+
//| Forward declarations                                             |
//+------------------------------------------------------------------+
bool   ParsePacComment(string comment, PacComment &out);
bool   TimeframeFromString(const string s, ENUM_TIMEFRAMES &tf);
string TimeframeToString(const ENUM_TIMEFRAMES tf);
bool   IsBuyOrderType(const ENUM_ORDER_TYPE t);
double NormalizePrice(const double price);
double NormalizeLot(const double lot);
void   LogPrint(const string msg);
void   LogAlert(const string msg);
void   NotifyInfo(const string msg, const bool doAlert);
string SideText(const int direction);
string GroupFromComment(const string comment);
void   NotifyNewPos1Orders(const LiveItem &items[]);
bool   TicketInList(const ulong ticket, const ulong &list[]);
void   RememberTicket(const ulong ticket, ulong &list[]);
bool   DealProcessed(const ulong deal);
void   MarkDealProcessed(const ulong deal);
int    FindGroupIndex(const string code);
int    FindBatchIndex(const string code);
int    FindSnapIndex(const ulong positionId);
void   UpsertPositionSnapshot(const ulong posTicket);
void   TryPlaceTestOrder();
void   RefreshState();
void   CollectItems(LiveItem &items[]);
void   UpdateSnapshots(const LiveItem &items[]);
void   SyncGroups(LiveItem &items[]);
void   MergeGroupState(PacGroup &dst, const PacGroup &src);
void   InitClccBarState(PacGroup &g);
void   TryAutoLayer(const LiveItem &items[]);
bool   GenerateLayers(PacGroup &g, const LiveItem &pos1);
void   CheckPos1TpSync();
void   SyncTpToOtherSlots(PacGroup &g, const LiveItem &items[], const double newTp);
bool   SamePrice(const double a, const double b);
void   CheckAllClcc();
bool   IsClBreak(const PacGroup &g, const double closePrice);
void   ExecuteClcc(PacGroup &g);
void   FlattenGroup(PacGroup &g);
void   DeletePendingInGroup(PacGroup &g);
void   ProcessTpBatches();
void   QueueTpReentry(const string groupCode, const Snapshot &snap);
void   RemoveTpBatchAt(const int index);
bool   PlaceReentry(const TpSlot &slot);
ENUM_ORDER_TYPE SelectPendingType(const bool isBuy, const double entry);
bool   PlaceOrder(const ENUM_ORDER_TYPE type, const double lot, const double price,
                  const double sl, const double tp, const string comment, const long magic);
bool   TradeOk();
void   ReportTradeError(const string action, const string groupCode);
void   UpdateVisuals();
void   UpsertClLine(const PacGroup &g);
void   UpsertClText(const PacGroup &g, const int barShift);
void   UpsertCountdown(const PacGroup &g, const LiveItem &items[], const int row);
void   UpsertHudLabel(const string name, const int x, const int y, const string text,
                      const color clr, const int fontSize, const string font);
void   CalcGroupProfits(const PacGroup &g, const LiveItem &items[], double &tpProfit, double &floatProfit);
double GroupEntryPrice(const PacGroup &g, const LiveItem &items[]);
void   DeleteGroupVisuals(const string groupCode);
void   DeleteAllVisuals();
void   CleanupOrphanVisuals();
bool   VisualGroupFromName(const string name, string &code);
string FormatHMS(int seconds);
datetime ServerNow();
bool   ItemMatchesGroup(const LiveItem &it, const PacGroup &g);

//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints((ulong)MathMax(InpDeviation, 0));
   g_trade.SetAsyncMode(false);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   g_testOrderPlaced = false;
   g_inRefresh       = false;
   g_syncingTp       = false;
   g_initScanDone    = false;
   g_clccGroup       = "";
   ArrayResize(g_groups, 0);
   ArrayResize(g_snaps, 0);
   ArrayResize(g_tpBatches, 0);
   ArrayResize(g_processedDeals, 0);
   ArrayResize(g_parseAlerted, 0);
   ArrayResize(g_ambiguousAlerted, 0);

   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      // TODO: CONFIRM WITH USER — EA mengasumsikan akun hedging agar tiap layer
      // tetap posisi terpisah (comment per slot). Di netting, posisi se-arah merge.
      LogAlert(_Symbol + " - bukan hedging");
     }

   if(!EventSetTimer(1))
      LogPrint("EventSetTimer(1) gagal — countdown mungkin hanya update saat ada tick.");

   RefreshState();
   LogPrint("Init OK. Magic=" + IntegerToString(InpMagic) +
            " MaxReentry=" + IntegerToString(InpMaxReentry) +
            " TestMode=" + (InpTestMode ? "true" : "false"));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteAllVisuals();
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(InpTestMode)
      TryPlaceTestOrder();
   RefreshState();
}

//+------------------------------------------------------------------+
void OnTimer()
{
   RefreshState();
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_POSITION && trans.position != 0)
      UpsertPositionSnapshot(trans.position);

   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
     {
      if(!g_inRefresh &&
         (trans.type == TRADE_TRANSACTION_ORDER_ADD ||
          trans.type == TRADE_TRANSACTION_ORDER_DELETE ||
          trans.type == TRADE_TRANSACTION_ORDER_UPDATE ||
          trans.type == TRADE_TRANSACTION_POSITION ||
          trans.type == TRADE_TRANSACTION_HISTORY_ADD))
         RefreshState();
      return;
     }

   if(trans.deal == 0 || DealProcessed(trans.deal))
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;

   const long entryFlag = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   const ulong posId    = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);

   if(entryFlag != DEAL_ENTRY_OUT && entryFlag != DEAL_ENTRY_INOUT)
     {
      if(entryFlag == DEAL_ENTRY_IN && trans.position != 0)
         UpsertPositionSnapshot(trans.position);
      else if(entryFlag == DEAL_ENTRY_IN && posId != 0)
        {
         if(PositionSelectByTicket(posId))
            UpsertPositionSnapshot(posId);
        }
      MarkDealProcessed(trans.deal);
      return;
     }

   MarkDealProcessed(trans.deal);

   const long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);

   Snapshot snap;
   snap.positionId = 0;
   snap.ticket     = 0;
   snap.comment    = "";
   snap.entry      = 0;
   snap.sl         = 0;
   snap.tp         = 0;
   snap.lot        = 0;
   snap.isBuy      = false;
   const int si = FindSnapIndex(posId);
   if(si >= 0)
      snap = g_snaps[si];
   else
     {
      snap.positionId = posId;
      snap.lot        = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
      snap.sl         = trans.price_sl;
      snap.tp         = trans.price_tp;
      if(!HistorySelectByPosition(posId))
         return;
      const int total = HistoryDealsTotal();
      bool foundIn = false;
      for(int i = 0; i < total; i++)
        {
         const ulong d = HistoryDealGetTicket(i);
         if(d == 0)
            continue;
         if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN)
            continue;
         snap.entry   = HistoryDealGetDouble(d, DEAL_PRICE);
         snap.comment = HistoryDealGetString(d, DEAL_COMMENT);
         snap.isBuy   = (HistoryDealGetInteger(d, DEAL_TYPE) == DEAL_TYPE_BUY);
         foundIn      = true;
         break;
        }
      if(!foundIn)
         return;
     }

   HistoryDealSelect(trans.deal);
   if(trans.price_tp > 0.0)
      snap.tp = trans.price_tp;
   if(trans.price_sl > 0.0)
      snap.sl = trans.price_sl;
   const double dealVol = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
   if(dealVol > 0.0)
      snap.lot = dealVol;
   if(snap.tp <= 0.0 && reason == DEAL_REASON_TP)
      snap.tp = HistoryDealGetDouble(trans.deal, DEAL_PRICE);

   PacComment pac;
   if(!ParsePacComment(snap.comment, pac))
      return;

   const int gi = FindGroupIndex(pac.groupCode);
   if(gi < 0)
      return;
   if(g_groups[gi].clExecuted || g_clccGroup == pac.groupCode)
      return;
   if(reason == DEAL_REASON_EXPERT)
      return;

   if(reason == DEAL_REASON_TP)
     {
      QueueTpReentry(pac.groupCode, snap);
      if(!g_inRefresh)
         RefreshState();
      return;
     }

   if(reason == DEAL_REASON_SL ||
      reason == DEAL_REASON_CLIENT ||
      reason == DEAL_REASON_MOBILE)
     {
      // Stop reentry HANYA untuk slot ini — cukup dengan tidak me-reentry.
      // Tidak ada blacklist permanen: order baru dengan comment yang sama = aktif lagi.
      LogPrint("Slot berhenti reentry (bukan TP): ticket/pos " +
               IntegerToString((long)posId) + " comment='" + snap.comment +
               "' reason=" + IntegerToString((int)reason));
      return;
     }

   LogPrint("Deal close diabaikan untuk reentry. comment='" + snap.comment +
            "' reason=" + IntegerToString((int)reason));
}

//+------------------------------------------------------------------+
//| TEST MODE                                                        |
//+------------------------------------------------------------------+
void TryPlaceTestOrder()
{
   if(g_testOrderPlaced)
      return;
   if(TimeCurrent() < InpTestDateTime)
      return;

   PacComment pac;
   if(!ParsePacComment(InpTestComment, pac))
     {
      LogAlert(_Symbol + " " + GroupFromComment(InpTestComment) +
               " parse fail '" + InpTestComment + "'");
      g_testOrderPlaced = true;
      return;
     }

   LogPrint("TestMode: memasang order simulasi comment='" + InpTestComment + "'");
   const bool ok = PlaceOrder(InpTestOrderType,
                              NormalizeLot(InpTestLot),
                              NormalizePrice(InpTestEntryPrice),
                              NormalizePrice(InpTestSL),
                              NormalizePrice(InpTestTP),
                              InpTestComment,
                              0);
   g_testOrderPlaced = true;
   if(!ok)
      ReportTradeError("OrderSend test", GroupFromComment(InpTestComment));
   else
      LogPrint("TestMode: order terpasang.");
}

//+------------------------------------------------------------------+
//| REFRESH                                                          |
//+------------------------------------------------------------------+
void RefreshState()
{
   if(g_inRefresh)
      return;
   g_inRefresh = true;

   LiveItem items[];
   CollectItems(items);
   UpdateSnapshots(items);
   SyncGroups(items);
   if(!g_initScanDone)
     {
      for(int i = 0; i < ArraySize(g_groups); i++)
         g_groups[i].orderNotified = true;
      g_initScanDone = true;
     }
   else
      NotifyNewPos1Orders(items);
   TryAutoLayer(items);
   CheckPos1TpSync();
   CheckAllClcc();

   for(int i = 0; i < ArraySize(g_groups); i++)
     {
      if(g_groups[i].clExecuted)
         FlattenGroup(g_groups[i]);
     }

   ProcessTpBatches();
   UpdateVisuals();

   g_inRefresh = false;
}

//+------------------------------------------------------------------+
void CollectItems(LiveItem &items[])
{
   ArrayResize(items, 0);

   const int posTotal = PositionsTotal();
   for(int i = 0; i < posTotal; i++)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      LiveItem it;
      it.ticket      = ticket;
      it.positionId  = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      it.isPosition  = true;
      it.comment     = PositionGetString(POSITION_COMMENT);
      it.price       = PositionGetDouble(POSITION_PRICE_OPEN);
      it.sl          = PositionGetDouble(POSITION_SL);
      it.tp          = PositionGetDouble(POSITION_TP);
      it.lot         = PositionGetDouble(POSITION_VOLUME);
      it.orderType   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                       ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      it.setupTime   = (datetime)PositionGetInteger(POSITION_TIME);
      it.parsed      = ParsePacComment(it.comment, it.pac);
      it.ignored     = false;

      const int n = ArraySize(items);
      ArrayResize(items, n + 1);
      items[n] = it;
     }

   const int ordTotal = OrdersTotal();
   for(int i = 0; i < ordTotal; i++)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;

      LiveItem it;
      it.ticket      = ticket;
      it.positionId  = 0;
      it.isPosition  = false;
      it.comment     = OrderGetString(ORDER_COMMENT);
      it.price       = OrderGetDouble(ORDER_PRICE_OPEN);
      it.sl          = OrderGetDouble(ORDER_SL);
      it.tp          = OrderGetDouble(ORDER_TP);
      it.lot         = OrderGetDouble(ORDER_VOLUME_CURRENT);
      if(it.lot <= 0.0)
         it.lot = OrderGetDouble(ORDER_VOLUME_INITIAL);
      it.orderType   = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      it.setupTime   = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      it.parsed      = ParsePacComment(it.comment, it.pac);
      it.ignored     = false;

      const int n = ArraySize(items);
      ArrayResize(items, n + 1);
      items[n] = it;
     }

   for(int i = 0; i < ArraySize(items); i++)
     {
      if(items[i].parsed)
         continue;
      // TODO: CONFIRM WITH USER — Alert parse-fail hanya jika comment mengandung '/'
      // (mirip format PAC). Comment kosong / milik EA lain diabaikan tanpa alert
      // supaya tidak spam di akun yang ada order non-PAC.
      if(StringFind(items[i].comment, "/") < 0)
         continue;
      if(TicketInList(items[i].ticket, g_parseAlerted))
         continue;
      RememberTicket(items[i].ticket, g_parseAlerted);
      LogAlert(_Symbol + " " + GroupFromComment(items[i].comment) +
               " parse fail #" + IntegerToString((long)items[i].ticket) +
               " '" + items[i].comment + "'");
     }
}

//+------------------------------------------------------------------+
void UpdateSnapshots(const LiveItem &items[])
{
   Snapshot fresh[];
   ArrayResize(fresh, 0);
   for(int i = 0; i < ArraySize(items); i++)
     {
      if(!items[i].isPosition || !items[i].parsed)
         continue;
      Snapshot s;
      s.positionId = items[i].positionId;
      s.ticket     = items[i].ticket;
      s.comment    = items[i].comment;
      s.entry      = items[i].price;
      s.sl         = items[i].sl;
      s.tp         = items[i].tp;
      s.lot        = items[i].lot;
      s.isBuy      = IsBuyOrderType(items[i].orderType);
      const int n = ArraySize(fresh);
      ArrayResize(fresh, n + 1);
      fresh[n] = s;
     }
   ArrayResize(g_snaps, ArraySize(fresh));
   for(int i = 0; i < ArraySize(fresh); i++)
      g_snaps[i] = fresh[i];
}

//+------------------------------------------------------------------+
void SyncGroups(LiveItem &items[])
{
   PacGroup next[];
   ArrayResize(next, 0);

   const int nItems = ArraySize(items);
   bool assigned[];
   ArrayResize(assigned, nItems);
   for(int a = 0; a < nItems; a++)
      assigned[a] = false;

   for(int i = 0; i < nItems; i++)
     {
      if(!items[i].parsed || assigned[i])
         continue;

      int oldest = i;
      for(int j = i + 1; j < nItems; j++)
        {
         if(!items[j].parsed || assigned[j])
            continue;
         if(items[j].pac.groupCode != items[i].pac.groupCode)
            continue;
         if(items[j].setupTime < items[oldest].setupTime)
            oldest = j;
        }

      PacGroup g;
      g.groupCode    = items[oldest].pac.groupCode;
      g.timeframe    = items[oldest].pac.timeframe;
      g.clPrice      = items[oldest].pac.clPrice;
      g.tfText       = items[oldest].pac.tfText;
      g.clText       = items[oldest].pac.clText;
      g.layerCount   = items[oldest].pac.layerCount;
      g.direction           = IsBuyOrderType(items[oldest].orderType) ? 1 : -1;
      g.startedAt           = items[oldest].setupTime;
      g.pos1Comment         = g.groupCode + IntegerToString(g.layerCount) + "1/" + g.tfText + "/" + g.clText;
      g.lastCheckedBarTime  = 0;
      g.reentryCount        = 0;
      g.layeringAttempted   = false;
      g.clExecuted          = false;
      g.pos1LastTp          = 0;
      g.pos1TpReady         = false;
      g.orderNotified       = false;

      int usedPos[];
      ArrayResize(usedPos, 0);

      for(int j = 0; j < nItems; j++)
        {
         if(!items[j].parsed)
            continue;
         if(items[j].pac.groupCode != g.groupCode)
            continue;

         const bool sameSetup =
            (items[j].pac.layerCount == g.layerCount) &&
            (items[j].pac.timeframe == g.timeframe) &&
            (MathAbs(items[j].pac.clPrice - g.clPrice) < _Point * 0.5);
         const int dir = IsBuyOrderType(items[j].orderType) ? 1 : -1;
         const bool sameDir = (dir == g.direction);

         bool dupPos = false;
         if(sameSetup && sameDir)
           {
            for(int p = 0; p < ArraySize(usedPos); p++)
              {
               if(usedPos[p] == items[j].pac.position)
                 {
                  dupPos = true;
                  break;
                 }
              }
           }

         if(!sameSetup || !sameDir || dupPos)
           {
            items[j].ignored = true;
            assigned[j] = true;
            if(!TicketInList(items[j].ticket, g_ambiguousAlerted))
              {
               RememberTicket(items[j].ticket, g_ambiguousAlerted);
               LogAlert(_Symbol + " " + g.groupCode + " ambigu #" +
                        IntegerToString((long)items[j].ticket) +
                        " '" + items[j].comment + "'");
              }
            continue;
           }

         assigned[j] = true;
         const int pn = ArraySize(usedPos);
         ArrayResize(usedPos, pn + 1);
         usedPos[pn] = items[j].pac.position;
         if(items[j].setupTime < g.startedAt)
            g.startedAt = items[j].setupTime;
         if(items[j].pac.position == 1)
           {
            g.pos1Comment = items[j].comment;
            g.pos1LastTp  = items[j].tp;
            g.pos1TpReady = true;
           }
        }

      const int oldIdx = FindGroupIndex(g.groupCode);
      if(oldIdx >= 0)
         MergeGroupState(g, g_groups[oldIdx]);
      else
         InitClccBarState(g);

      const int nn = ArraySize(next);
      ArrayResize(next, nn + 1);
      next[nn] = g;
     }

   for(int i = 0; i < ArraySize(g_groups); i++)
     {
      bool still = false;
      for(int j = 0; j < ArraySize(next); j++)
        {
         if(next[j].groupCode == g_groups[i].groupCode)
           {
            still = true;
            break;
           }
        }
      if(!still)
         DeleteGroupVisuals(g_groups[i].groupCode);
     }

   ArrayResize(g_groups, ArraySize(next));
   for(int i = 0; i < ArraySize(next); i++)
      g_groups[i] = next[i];
}

//+------------------------------------------------------------------+
void MergeGroupState(PacGroup &dst, const PacGroup &src)
{
   dst.lastCheckedBarTime = src.lastCheckedBarTime;
   dst.reentryCount       = src.reentryCount;
   dst.layeringAttempted  = src.layeringAttempted;
   dst.clExecuted         = src.clExecuted;
   dst.pos1LastTp         = src.pos1LastTp;
   dst.pos1TpReady        = src.pos1TpReady;
   dst.orderNotified      = src.orderNotified;
}

//+------------------------------------------------------------------+
void InitClccBarState(PacGroup &g)
{
   const datetime currentBar = iTime(_Symbol, g.timeframe, 0);
   if(currentBar == 0)
     {
      g.lastCheckedBarTime = 0;
      return;
     }

   const int bars = Bars(_Symbol, g.timeframe);
   int startIndex = 0;
   for(int i = 0; i < bars && i < 100; i++)
     {
      const datetime t = iTime(_Symbol, g.timeframe, i);
      if(t > 0 && t <= g.startedAt)
        {
         startIndex = i;
         break;
        }
     }

   if(startIndex >= 1)
     {
      for(int i = startIndex; i >= 1; i--)
        {
         const double cl = iClose(_Symbol, g.timeframe, i);
         if(cl <= 0.0)
            continue;
         if(IsClBreak(g, cl))
           {
            LogPrint("CLCC catch-up grup " + g.groupCode +
                     " — candle index " + IntegerToString(i) +
                     " close=" + DoubleToString(cl, _Digits));
            g.lastCheckedBarTime = currentBar;
            ExecuteClcc(g);
            return;
           }
        }
     }

   g.lastCheckedBarTime = currentBar;
}

//+------------------------------------------------------------------+
//| AUTO LAYERING                                                    |
//+------------------------------------------------------------------+
void TryAutoLayer(const LiveItem &items[])
{
   for(int gi = 0; gi < ArraySize(g_groups); gi++)
     {
      PacGroup g = g_groups[gi];
      if(g.clExecuted || g.layeringAttempted)
         continue;
      if(g.layerCount <= 1)
        {
         g_groups[gi].layeringAttempted = true;
         continue;
        }

      int members = 0;
      int pos1Idx = -1;
      for(int i = 0; i < ArraySize(items); i++)
        {
         if(!items[i].parsed || items[i].ignored)
            continue;
         if(!ItemMatchesGroup(items[i], g))
            continue;
         members++;
         if(items[i].pac.position == 1)
            pos1Idx = i;
        }

      if(members > 1)
        {
         g_groups[gi].layeringAttempted = true;
         continue;
        }

      // TODO: CONFIRM WITH USER — jika setelah restart hanya sisa posisi 1
      // (layer lain sudah dihapus manual), EA akan generate ulang layer.
      // Spec: trigger = "belum ada order lain di grup yang sama".
      if(members == 1 && pos1Idx >= 0)
        {
         g_groups[gi].layeringAttempted = true;
         GenerateLayers(g_groups[gi], items[pos1Idx]);
        }
     }
}

//+------------------------------------------------------------------+
bool GenerateLayers(PacGroup &g, const LiveItem &pos1)
{
   const double entry1   = pos1.price;
   const double distance = MathAbs(entry1 - g.clPrice);
   if(distance <= _Point)
     {
      LogAlert(_Symbol + " " + SideText(g.direction) + " " + g.groupCode +
               " layer skip, CL dekat");
      return(false);
     }

   const int    arah   = (g.clPrice > entry1) ? 1 : -1;
   const double buffer = InpLayerBufferPoints * _Point;
   const bool   isBuy  = (g.direction > 0);
   const double lot    = NormalizeLot(pos1.lot);
   const double sl     = pos1.sl;
   const double tp     = pos1.tp;

   LogPrint("Auto-layer grup " + g.groupCode +
            " N=" + IntegerToString(g.layerCount) +
            " entry1=" + DoubleToString(entry1, _Digits) +
            " CL=" + DoubleToString(g.clPrice, _Digits) +
            " arah=" + IntegerToString(arah));

   int okCount = 0;
   for(int i = 2; i <= g.layerCount; i++)
     {
      double entry = entry1 + (distance * (double)(i - 1) / (double)g.layerCount) * arah;
      if(i == g.layerCount && buffer > 0.0)
        {
         double cand = entry - arah * buffer;
         if(arah < 0)
           {
            if(cand <= g.clPrice)
               cand = g.clPrice + MathMax(buffer, _Point);
            if(cand >= entry1)
               cand = entry;
           }
         else
           {
            if(cand >= g.clPrice)
               cand = g.clPrice - MathMax(buffer, _Point);
            if(cand <= entry1)
               cand = entry;
           }
         entry = cand;
        }
      entry = NormalizePrice(entry);

      const string cmt = g.groupCode + IntegerToString(g.layerCount) + IntegerToString(i) +
                         "/" + g.tfText + "/" + g.clText;
      const ENUM_ORDER_TYPE otype = SelectPendingType(isBuy, entry);

      if(PlaceOrder(otype, lot, entry, sl, tp, cmt, InpMagic))
        {
         okCount++;
         LogPrint("Layer terpasang: " + cmt + " @ " + DoubleToString(entry, _Digits) +
                  " type=" + EnumToString(otype));
        }
      else
         ReportTradeError("Auto-layer @ " + DoubleToString(entry, _Digits), g.groupCode);
     }

   if(okCount > 0)
     {
      const string side = isBuy ? "Buy" : "Sell";
      NotifyInfo("Layer " + _Symbol + " " + side + " " + g.groupCode + " " +
                 IntegerToString(okCount) + "/" + IntegerToString(g.layerCount - 1) +
                 " layer Sukses",
                 InpAlertOnLayer);
     }
   return(okCount == g.layerCount - 1);
}

//+------------------------------------------------------------------+
bool SamePrice(const double a, const double b)
{
   return(MathAbs(a - b) < _Point * 0.5);
}

//+------------------------------------------------------------------+
void CheckPos1TpSync()
{
   if(g_syncingTp)
      return;

   LiveItem items[];
   CollectItems(items);

   for(int gi = 0; gi < ArraySize(g_groups); gi++)
     {
      if(g_groups[gi].clExecuted)
         continue;

      int pos1Idx = -1;
      for(int i = 0; i < ArraySize(items); i++)
        {
         if(!items[i].parsed || items[i].ignored)
            continue;
         if(!ItemMatchesGroup(items[i], g_groups[gi]))
            continue;
         if(items[i].pac.position == 1)
           {
            pos1Idx = i;
            break;
           }
        }

      if(pos1Idx < 0)
         continue;

      const double tp1 = items[pos1Idx].tp;
      if(!g_groups[gi].pos1TpReady)
        {
         g_groups[gi].pos1LastTp  = tp1;
         g_groups[gi].pos1TpReady = true;
         continue;
        }
      if(SamePrice(tp1, g_groups[gi].pos1LastTp))
         continue;

      LogPrint("TP order trader (posisi 1) grup " + g_groups[gi].groupCode +
               " berubah " + DoubleToString(g_groups[gi].pos1LastTp, _Digits) +
               " -> " + DoubleToString(tp1, _Digits) + ". Layer mengikuti.");
      g_groups[gi].pos1LastTp = tp1;
      SyncTpToOtherSlots(g_groups[gi], items, tp1);
     }
}

//+------------------------------------------------------------------+
void SyncTpToOtherSlots(PacGroup &g, const LiveItem &items[], const double newTp)
{
   g_syncingTp = true;
   const double tp = NormalizePrice(newTp);
   int changed = 0;

   for(int i = 0; i < ArraySize(items); i++)
     {
      if(!items[i].parsed || items[i].ignored)
         continue;
      if(!ItemMatchesGroup(items[i], g))
         continue;
      if(items[i].pac.position == 1)
         continue;
      if(SamePrice(items[i].tp, tp))
         continue;

      bool ok = false;
      if(items[i].isPosition)
         ok = g_trade.PositionModify(items[i].ticket, items[i].sl, tp);
      else
        {
         ENUM_ORDER_TYPE_TIME ttime = ORDER_TIME_GTC;
         datetime exp = 0;
         if(OrderSelect(items[i].ticket))
           {
            ttime = (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME);
            exp   = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
           }
         ok = g_trade.OrderModify(items[i].ticket, items[i].price, items[i].sl, tp, ttime, exp);
        }

      if(!ok || !TradeOk())
         ReportTradeError("Sync TP layer #" + IntegerToString((long)items[i].ticket), g.groupCode);
      else
        {
         changed++;
         LogPrint("TP layer disamakan: " + items[i].comment +
                  " -> " + DoubleToString(tp, _Digits));
        }
     }

   if(changed > 0)
      LogPrint("Sync TP grup " + g.groupCode + ": " + IntegerToString(changed) + " layer diubah.");
   g_syncingTp = false;
}

//+------------------------------------------------------------------+
//| CLCC                                                             |
//+------------------------------------------------------------------+
void CheckAllClcc()
{
   for(int i = 0; i < ArraySize(g_groups); i++)
     {
      if(g_groups[i].clExecuted)
         continue;

      const ENUM_TIMEFRAMES tf = g_groups[i].timeframe;
      const datetime currentBar = iTime(_Symbol, tf, 0);
      if(currentBar == 0)
         continue;

      if(g_groups[i].lastCheckedBarTime == 0)
        {
         g_groups[i].lastCheckedBarTime = currentBar;
         continue;
        }
      if(currentBar == g_groups[i].lastCheckedBarTime)
         continue;

      int idx = iBarShift(_Symbol, tf, g_groups[i].lastCheckedBarTime, false);
      if(idx < 1)
         idx = 1;
      if(idx > 100)
         idx = 100;

      bool broke = false;
      for(int b = idx; b >= 1; b--)
        {
         const double cl = iClose(_Symbol, tf, b);
         if(cl <= 0.0)
            continue;
         if(IsClBreak(g_groups[i], cl))
           {
            LogPrint("CLCC grup " + g_groups[i].groupCode +
                     " break. TF=" + g_groups[i].tfText +
                     " close[" + IntegerToString(b) + "]=" + DoubleToString(cl, _Digits) +
                     " CL=" + DoubleToString(g_groups[i].clPrice, _Digits));
            ExecuteClcc(g_groups[i]);
            broke = true;
            break;
           }
        }

      g_groups[i].lastCheckedBarTime = currentBar;
      if(broke)
         continue;
     }
}

//+------------------------------------------------------------------+
bool IsClBreak(const PacGroup &g, const double closePrice)
{
   if(g.direction > 0)
      return(closePrice < g.clPrice);
   return(closePrice > g.clPrice);
}

//+------------------------------------------------------------------+
void ExecuteClcc(PacGroup &g)
{
   g.clExecuted = true;
   g_clccGroup  = g.groupCode;

   LiveItem items[];
   CollectItems(items);
   double tpProfit = 0;
   double floatProfit = 0;
   CalcGroupProfits(g, items, tpProfit, floatProfit);

   FlattenGroup(g);
   DeleteGroupVisuals(g.groupCode);
   NotifyInfo("CLCC " + _Symbol + " " + SideText(g.direction) + " " + g.groupCode +
              " [" + DoubleToString(floatProfit, 2) + "]",
              InpAlertOnCL);
   g_clccGroup = "";
}

//+------------------------------------------------------------------+
void FlattenGroup(PacGroup &g)
{
   LiveItem items[];
   CollectItems(items);

   for(int i = 0; i < ArraySize(items); i++)
     {
      if(!items[i].parsed || items[i].ignored)
         continue;
      if(!ItemMatchesGroup(items[i], g))
         continue;

      if(items[i].isPosition)
        {
         if(!g_trade.PositionClose(items[i].ticket) || !TradeOk())
            ReportTradeError("PositionClose #" + IntegerToString((long)items[i].ticket), g.groupCode);
        }
      else
        {
         if(!g_trade.OrderDelete(items[i].ticket) || !TradeOk())
            ReportTradeError("OrderDelete #" + IntegerToString((long)items[i].ticket), g.groupCode);
        }
     }
}

//+------------------------------------------------------------------+
void DeletePendingInGroup(PacGroup &g)
{
   LiveItem items[];
   CollectItems(items);

   int deleted = 0;
   for(int i = 0; i < ArraySize(items); i++)
     {
      if(!items[i].parsed || items[i].ignored || items[i].isPosition)
         continue;
      if(!ItemMatchesGroup(items[i], g))
         continue;

      if(!g_trade.OrderDelete(items[i].ticket) || !TradeOk())
         ReportTradeError("OrderDelete #" + IntegerToString((long)items[i].ticket), g.groupCode);
      else
        {
         deleted++;
         LogPrint("MaxReentry: pending dihapus ticket #" +
                  IntegerToString((long)items[i].ticket) + " comment='" + items[i].comment + "'");
        }
     }

   NotifyInfo("Max Reentry " + _Symbol + " " + SideText(g.direction) + " " + g.groupCode +
              " (" + IntegerToString(deleted) + " Pending dihapus)",
              InpAlertOnReentry);
}

//+------------------------------------------------------------------+
bool ItemMatchesGroup(const LiveItem &it, const PacGroup &g)
{
   if(it.pac.groupCode != g.groupCode)
      return(false);
   if(it.pac.layerCount != g.layerCount)
      return(false);
   if(it.pac.timeframe != g.timeframe)
      return(false);
   if(MathAbs(it.pac.clPrice - g.clPrice) >= _Point * 0.5)
      return(false);
   const int dir = IsBuyOrderType(it.orderType) ? 1 : -1;
   return(dir == g.direction);
}

//+------------------------------------------------------------------+
//| REENTRY                                                          |
//+------------------------------------------------------------------+
void QueueTpReentry(const string groupCode, const Snapshot &snap)
{
   int bi = FindBatchIndex(groupCode);
   if(bi < 0)
     {
      TpBatch b;
      b.groupCode      = groupCode;
      b.windowStartMs  = GetTickCount64();
      ArrayResize(b.slots, 0);
      const int n = ArraySize(g_tpBatches);
      ArrayResize(g_tpBatches, n + 1);
      g_tpBatches[n] = b;
      bi = n;
     }

   TpSlot slot;
   slot.comment = snap.comment;
   slot.entry   = snap.entry;
   slot.sl      = snap.sl;
   slot.tp      = snap.tp;
   slot.lot     = snap.lot;
   slot.isBuy   = snap.isBuy;

   const int ns = ArraySize(g_tpBatches[bi].slots);
      ArrayResize(g_tpBatches[bi].slots, ns + 1);
      g_tpBatches[bi].slots[ns] = slot;
}

//+------------------------------------------------------------------+
void RemoveTpBatchAt(const int index)
{
   const int n = ArraySize(g_tpBatches);
   if(index < 0 || index >= n)
      return;
   for(int i = index; i < n - 1; i++)
      g_tpBatches[i] = g_tpBatches[i + 1];
   ArrayResize(g_tpBatches, n - 1);
}

//+------------------------------------------------------------------+
void ProcessTpBatches()
{
   const ulong nowMs = GetTickCount64();
   const ulong win   = (ulong)MathMax(InpTpWindowMs, 100);

   for(int i = ArraySize(g_tpBatches) - 1; i >= 0; i--)
     {
      if(nowMs - g_tpBatches[i].windowStartMs < win)
         continue;

      const string code = g_tpBatches[i].groupCode;
      const int gi = FindGroupIndex(code);
      if(gi < 0 || g_groups[gi].clExecuted)
        {
         RemoveTpBatchAt(i);
         continue;
        }

      if(g_groups[gi].reentryCount >= InpMaxReentry)
        {
         DeletePendingInGroup(g_groups[gi]);
         RemoveTpBatchAt(i);
         continue;
        }

      int okCount = 0;
      for(int s = 0; s < ArraySize(g_tpBatches[i].slots); s++)
        {
         if(PlaceReentry(g_tpBatches[i].slots[s]))
            okCount++;
        }

      if(okCount > 0)
        {
         g_groups[gi].reentryCount++;
         NotifyInfo("Reentry " + _Symbol + " " + SideText(g_groups[gi].direction) + " " + code + " " +
                    IntegerToString(g_groups[gi].reentryCount) + "/" +
                    IntegerToString(InpMaxReentry) + " Max Reentry Sukses",
                    InpAlertOnReentry);
        }

      RemoveTpBatchAt(i);
     }
}

//+------------------------------------------------------------------+
bool PlaceReentry(const TpSlot &slot)
{
   const double entry = NormalizePrice(slot.entry);
   const double lot   = NormalizeLot(slot.lot);
   const ENUM_ORDER_TYPE otype = SelectPendingType(slot.isBuy, entry);

   if(!PlaceOrder(otype, lot, entry, slot.sl, slot.tp, slot.comment, InpMagic))
     {
      ReportTradeError("Reentry @ " + DoubleToString(entry, _Digits), GroupFromComment(slot.comment));
      return(false);
     }
   LogPrint("Reentry terpasang: " + slot.comment + " @ " + DoubleToString(entry, _Digits) +
            " type=" + EnumToString(otype));
   return(true);
}

//+------------------------------------------------------------------+
//| ORDER HELPERS                                                    |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE SelectPendingType(const bool isBuy, const double entry)
{
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(isBuy)
      return((entry < ask) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_BUY_STOP);
   return((entry > bid) ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_SELL_STOP);
}

//+------------------------------------------------------------------+
bool PlaceOrder(const ENUM_ORDER_TYPE type, const double lot, const double price,
                const double sl, const double tp, const string comment, const long magic)
{
   g_trade.SetExpertMagicNumber(magic);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   bool ok = false;
   switch(type)
     {
      case ORDER_TYPE_BUY:
         ok = g_trade.Buy(lot, _Symbol, 0, sl, tp, comment);
         break;
      case ORDER_TYPE_SELL:
         ok = g_trade.Sell(lot, _Symbol, 0, sl, tp, comment);
         break;
      case ORDER_TYPE_BUY_LIMIT:
         ok = g_trade.BuyLimit(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
         break;
      case ORDER_TYPE_SELL_LIMIT:
         ok = g_trade.SellLimit(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
         break;
      case ORDER_TYPE_BUY_STOP:
         ok = g_trade.BuyStop(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
         break;
      case ORDER_TYPE_SELL_STOP:
         ok = g_trade.SellStop(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
         break;
      case ORDER_TYPE_BUY_STOP_LIMIT:
      case ORDER_TYPE_SELL_STOP_LIMIT:
         LogAlert(_Symbol + " " + GroupFromComment(comment) +
                  " tipe " + EnumToString(type) + " belum didukung");
         g_trade.SetExpertMagicNumber(InpMagic);
         return(false);
      default:
         LogAlert(_Symbol + " " + GroupFromComment(comment) + " tipe order tidak valid");
         g_trade.SetExpertMagicNumber(InpMagic);
         return(false);
     }

   const bool result = ok && TradeOk();
   g_trade.SetExpertMagicNumber(InpMagic);
   return(result);
}

//+------------------------------------------------------------------+
bool TradeOk()
{
   const uint r = g_trade.ResultRetcode();
   return(r == TRADE_RETCODE_DONE ||
          r == TRADE_RETCODE_DONE_PARTIAL ||
          r == TRADE_RETCODE_PLACED ||
          r == TRADE_RETCODE_NO_CHANGES);
}

//+------------------------------------------------------------------+
void ReportTradeError(const string action, const string groupCode)
{
   const uint  rc   = g_trade.ResultRetcode();
   const int   err  = GetLastError();
   string gcode = groupCode;
   if(StringLen(gcode) == 0)
      gcode = GroupFromComment(action);
   if(StringLen(gcode) == 0)
      gcode = "-";
   const string msg = _Symbol + " " + gcode + " " + action +
                      " gagal. retcode=" + IntegerToString((int)rc) +
                      " (" + g_trade.ResultRetcodeDescription() + ") lastError=" +
                      IntegerToString(err);
   LogAlert(msg);
}

//+------------------------------------------------------------------+
//| VISUAL                                                           |
//+------------------------------------------------------------------+
void UpdateVisuals()
{
   CleanupOrphanVisuals();

   LiveItem items[];
   CollectItems(items);

   string codes[];
   double entries[];
   ArrayResize(codes, 0);
   ArrayResize(entries, 0);
   for(int i = 0; i < ArraySize(g_groups); i++)
     {
      if(g_groups[i].clExecuted)
        {
         DeleteGroupVisuals(g_groups[i].groupCode);
         continue;
        }
      const int n = ArraySize(codes);
      ArrayResize(codes, n + 1);
      ArrayResize(entries, n + 1);
      codes[n]   = g_groups[i].groupCode;
      entries[n] = GroupEntryPrice(g_groups[i], items);
     }

   for(int a = 0; a < ArraySize(codes); a++)
     {
      for(int b = a + 1; b < ArraySize(codes); b++)
        {
         if(entries[b] > entries[a])
           {
            const string ts = codes[a];
            codes[a] = codes[b];
            codes[b] = ts;
            const double te = entries[a];
            entries[a] = entries[b];
            entries[b] = te;
           }
        }
     }

   int clShift[];
   ArrayResize(clShift, ArraySize(codes));
   for(int i = 0; i < ArraySize(clShift); i++)
      clShift[i] = 0;

   int order[];
   ArrayResize(order, ArraySize(codes));
   for(int i = 0; i < ArraySize(codes); i++)
      order[i] = i;
   for(int a = 0; a < ArraySize(order); a++)
     {
      for(int b = a + 1; b < ArraySize(order); b++)
        {
         const int ga = FindGroupIndex(codes[order[a]]);
         const int gb = FindGroupIndex(codes[order[b]]);
         if(ga < 0 || gb < 0)
            continue;
         if(g_groups[gb].clPrice > g_groups[ga].clPrice)
           {
            const int tmp = order[a];
            order[a] = order[b];
            order[b] = tmp;
           }
        }
     }

   const double pmax = ChartGetDouble(0, CHART_PRICE_MAX);
   const double pmin = ChartGetDouble(0, CHART_PRICE_MIN);
   double near = 20.0 * _Point;
   if(pmax > pmin)
      near = MathMax(near, (pmax - pmin) * 0.02);

   for(int k = 0; k < ArraySize(order); k++)
     {
      const int i = order[k];
      const int gi = FindGroupIndex(codes[i]);
      if(gi < 0)
         continue;
      int sh = 0;
      for(int m = 0; m < k; m++)
        {
         const int j = order[m];
         const int gj = FindGroupIndex(codes[j]);
         if(gj < 0)
            continue;
         if(MathAbs(g_groups[gi].clPrice - g_groups[gj].clPrice) < near)
            sh = MathMax(sh, clShift[j] + 3);
        }
      clShift[i] = sh;
     }

   int row = 0;
   for(int c = 0; c < ArraySize(codes); c++)
     {
      const int gi = FindGroupIndex(codes[c]);
      if(gi < 0)
         continue;
      UpsertClLine(g_groups[gi]);
      UpsertClText(g_groups[gi], clShift[c]);
      UpsertCountdown(g_groups[gi], items, row);
      row++;
     }
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void UpsertClLine(const PacGroup &g)
{
   const string name = PREFIX_CL + g.groupCode;
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, g.clPrice))
        {
         LogPrint("Gagal ObjectCreate " + name);
         return;
        }
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrOrange);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, "CL " + g.groupCode);
     }
   ObjectSetDouble(0, name, OBJPROP_PRICE, g.clPrice);
}

//+------------------------------------------------------------------+
void UpsertClText(const PacGroup &g, const int barShift)
{
   const string name = PREFIX_CLTEXT + g.groupCode;
   const int shift = (barShift < 0) ? 0 : barShift;
   datetime t = iTime(_Symbol, PERIOD_CURRENT, shift);
   if(t == 0)
      t = TimeCurrent() - (datetime)(shift * PeriodSeconds(PERIOD_CURRENT));

   double offset = 0;
   const double pmax = ChartGetDouble(0, CHART_PRICE_MAX);
   const double pmin = ChartGetDouble(0, CHART_PRICE_MIN);
   if(pmax > pmin)
      offset = (pmax - pmin) * 0.012;
   if(offset <= 0.0)
      offset = 15.0 * _Point;

   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, g.clPrice + offset))
        {
         LogPrint("Gagal ObjectCreate " + name);
         return;
        }
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrOrange);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
     }
   ObjectSetString(0, name, OBJPROP_TEXT, " " + g.groupCode);
   ObjectMove(0, name, 0, t, g.clPrice + offset);
}

//+------------------------------------------------------------------+
void UpsertCountdown(const PacGroup &g, const LiveItem &items[], const int row)
{
   ObjectDelete(0, PREFIX_CD + g.groupCode + "_L");
   ObjectDelete(0, PREFIX_CD + g.groupCode + "_T");
   ObjectDelete(0, PREFIX_CD + g.groupCode + "_P");
   ObjectDelete(0, PREFIX_CD + g.groupCode + "_S");
   ObjectDelete(0, PREFIX_CD + g.groupCode + "_F");

   const int fontSize = 9;
   const int x = 8;
   const int y = 5 * fontSize + row * (fontSize + 6);

   const datetime barOpen = iTime(_Symbol, g.timeframe, 0);
   int remain = 0;
   if(barOpen > 0)
     {
      const datetime closeAt = barOpen + (datetime)PeriodSeconds(g.timeframe);
      remain = (int)(closeAt - ServerNow());
     }

   double tpProfit    = 0;
   double floatProfit = 0;
   CalcGroupProfits(g, items, tpProfit, floatProfit);

   const string arah = (g.direction > 0) ? "BUY" : "SELL";
   const string text = arah + " " + g.groupCode + IntegerToString(g.layerCount) + " " +
                       g.tfText + " [" + FormatHMS(remain) + "] " +
                       DoubleToString(tpProfit, 2) + "/" + DoubleToString(floatProfit, 2);

   UpsertHudLabel(PREFIX_CD + g.groupCode, x, y, text, clrOrange, fontSize, "Arial");
}

//+------------------------------------------------------------------+
void UpsertHudLabel(const string name, const int x, const int y, const string text,
                    const color clr, const int fontSize, const string font)
{
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
        {
         LogPrint("Gagal ObjectCreate " + name);
         return;
        }
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
void CalcGroupProfits(const PacGroup &g, const LiveItem &items[], double &tpProfit, double &floatProfit)
{
   tpProfit    = 0;
   floatProfit = 0;

   const ENUM_ORDER_TYPE otype = (g.direction > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double mark = (g.direction > 0) ? bid : ask;

   for(int i = 0; i < ArraySize(items); i++)
     {
      if(!items[i].parsed || items[i].ignored)
         continue;
      if(!ItemMatchesGroup(items[i], g))
         continue;
      if(items[i].lot <= 0.0 || items[i].price <= 0.0)
         continue;

      if(items[i].tp > 0.0)
        {
         double p = 0;
         if(OrderCalcProfit(otype, _Symbol, items[i].lot, items[i].price, items[i].tp, p))
            tpProfit += p;
        }
      if(items[i].isPosition && mark > 0.0)
        {
         double p = 0;
         if(OrderCalcProfit(otype, _Symbol, items[i].lot, items[i].price, mark, p))
            floatProfit += p;
        }
     }
}

//+------------------------------------------------------------------+
double GroupEntryPrice(const PacGroup &g, const LiveItem &items[])
{
   double pos1 = 0;
   double any  = 0;
   bool hasPos1 = false;
   for(int i = 0; i < ArraySize(items); i++)
     {
      if(!items[i].parsed || items[i].ignored)
         continue;
      if(!ItemMatchesGroup(items[i], g))
         continue;
      if(items[i].price <= 0.0)
         continue;
      if(items[i].pac.position == 1)
        {
         pos1 = items[i].price;
         hasPos1 = true;
        }
      if(any == 0.0 || items[i].price > any)
         any = items[i].price;
     }
   return(hasPos1 ? pos1 : any);
}

//+------------------------------------------------------------------+
void DeleteGroupVisuals(const string groupCode)
{
   ObjectDelete(0, PREFIX_CL + groupCode);
   ObjectDelete(0, PREFIX_CLTEXT + groupCode);
   ObjectDelete(0, PREFIX_CD + groupCode);
   ObjectDelete(0, PREFIX_CD + groupCode + "_L");
   ObjectDelete(0, PREFIX_CD + groupCode + "_T");
   ObjectDelete(0, PREFIX_CD + groupCode + "_P");
   ObjectDelete(0, PREFIX_CD + groupCode + "_S");
   ObjectDelete(0, PREFIX_CD + groupCode + "_F");
   ObjectDelete(0, PREFIX_CD_OLD + groupCode);
}

//+------------------------------------------------------------------+
void DeleteAllVisuals()
{
   const int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      const string name = ObjectName(0, i, 0, -1);
      string code = "";
      if(VisualGroupFromName(name, code))
         ObjectDelete(0, name);
     }
}

//+------------------------------------------------------------------+
void CleanupOrphanVisuals()
{
   const int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      const string name = ObjectName(0, i, 0, -1);
      string code = "";
      if(!VisualGroupFromName(name, code))
         continue;
      if(FindGroupIndex(code) < 0)
         ObjectDelete(0, name);
     }
}

//+------------------------------------------------------------------+
bool VisualGroupFromName(const string name, string &code)
{
   code = "";
   if(StringFind(name, PREFIX_CLTEXT) == 0)
     {
      code = StringSubstr(name, StringLen(PREFIX_CLTEXT));
      return(StringLen(code) > 0);
     }
   if(StringFind(name, PREFIX_CL) == 0)
     {
      code = StringSubstr(name, StringLen(PREFIX_CL));
      return(StringLen(code) > 0);
     }
   if(StringFind(name, PREFIX_CD_OLD) == 0)
     {
      code = StringSubstr(name, StringLen(PREFIX_CD_OLD));
      return(StringLen(code) > 0);
     }
   if(StringFind(name, PREFIX_CD) == 0)
     {
      const string rest = StringSubstr(name, StringLen(PREFIX_CD));
      const int u = StringFind(rest, "_");
      code = (u > 0) ? StringSubstr(rest, 0, u) : rest;
      return(StringLen(code) > 0);
     }
   return(false);
}

//+------------------------------------------------------------------+
string FormatHMS(int seconds)
{
   if(seconds < 0)
      seconds = 0;
   const int hh = seconds / 3600;
   const int mm = (seconds % 3600) / 60;
   const int ss = seconds % 60;
   return(StringFormat("%02d:%02d:%02d", hh, mm, ss));
}

//+------------------------------------------------------------------+
datetime ServerNow()
{
   // Spec minta waktu server, bukan jam PC/VPS. TimeTradeServer() tetap
   // waktu server dan terus maju meski tidak ada tick (market sepi).
   datetime t = TimeTradeServer();
   if(t <= 0)
      t = TimeCurrent();
   return(t);
}

//+------------------------------------------------------------------+
//| PARSE                                                            |
//+------------------------------------------------------------------+
bool ParsePacComment(string comment, PacComment &out)
{
   out.groupCode  = "";
   out.layerCount = 0;
   out.position   = 0;
   out.timeframe  = PERIOD_CURRENT;
   out.clPrice    = 0;
   out.tfText     = "";
   out.clText     = "";
   StringTrimLeft(comment);
   StringTrimRight(comment);
   if(StringLen(comment) == 0)
      return(false);

   string parts[];
   const ushort sep = StringGetCharacter("/", 0);
   if(StringSplit(comment, sep, parts) != 3)
      return(false);

   StringTrimLeft(parts[0]);
   StringTrimRight(parts[0]);
   StringTrimLeft(parts[1]);
   StringTrimRight(parts[1]);
   StringTrimLeft(parts[2]);
   StringTrimRight(parts[2]);

   // v1: 1 huruf grup + 1 digit jumlah layer + 1 digit posisi (contoh A31)
   // TODO: CONFIRM WITH USER — group code multi-huruf / layer > 9 belum didukung.
   if(StringLen(parts[0]) != 3)
      return(false);

   const ushort c0 = StringGetCharacter(parts[0], 0);
   const ushort c1 = StringGetCharacter(parts[0], 1);
   const ushort c2 = StringGetCharacter(parts[0], 2);
   const bool letter = ((c0 >= 'A' && c0 <= 'Z') || (c0 >= 'a' && c0 <= 'z'));
   if(!letter || c1 < '0' || c1 > '9' || c2 < '0' || c2 > '9')
      return(false);

   out.groupCode  = StringSubstr(parts[0], 0, 1);
   out.layerCount = (int)(c1 - '0');
   out.position   = (int)(c2 - '0');
   if(out.layerCount < 1 || out.position < 1 || out.position > out.layerCount)
      return(false);

   if(!TimeframeFromString(parts[1], out.timeframe))
      return(false);
   out.tfText = parts[1];

   out.clPrice = StringToDouble(parts[2]);
   if(out.clPrice <= 0.0)
      return(false);
   out.clText = parts[2];
   return(true);
}

//+------------------------------------------------------------------+
bool TimeframeFromString(const string s, ENUM_TIMEFRAMES &tf)
{
   if(s == "M1")  { tf = PERIOD_M1;  return(true); }
   if(s == "M2")  { tf = PERIOD_M2;  return(true); }
   if(s == "M3")  { tf = PERIOD_M3;  return(true); }
   if(s == "M4")  { tf = PERIOD_M4;  return(true); }
   if(s == "M5")  { tf = PERIOD_M5;  return(true); }
   if(s == "M6")  { tf = PERIOD_M6;  return(true); }
   if(s == "M10") { tf = PERIOD_M10; return(true); }
   if(s == "M12") { tf = PERIOD_M12; return(true); }
   if(s == "M15") { tf = PERIOD_M15; return(true); }
   if(s == "M20") { tf = PERIOD_M20; return(true); }
   if(s == "M30") { tf = PERIOD_M30; return(true); }
   if(s == "H1")  { tf = PERIOD_H1;  return(true); }
   if(s == "H2")  { tf = PERIOD_H2;  return(true); }
   if(s == "H3")  { tf = PERIOD_H3;  return(true); }
   if(s == "H4")  { tf = PERIOD_H4;  return(true); }
   if(s == "H6")  { tf = PERIOD_H6;  return(true); }
   if(s == "H8")  { tf = PERIOD_H8;  return(true); }
   if(s == "H12") { tf = PERIOD_H12; return(true); }
   if(s == "D1")  { tf = PERIOD_D1;  return(true); }
   if(s == "W1")  { tf = PERIOD_W1;  return(true); }
   if(s == "MN1") { tf = PERIOD_MN1; return(true); }
   return(false);
}

//+------------------------------------------------------------------+
string TimeframeToString(const ENUM_TIMEFRAMES tf)
{
   switch(tf)
     {
      case PERIOD_M1:  return("M1");
      case PERIOD_M2:  return("M2");
      case PERIOD_M3:  return("M3");
      case PERIOD_M4:  return("M4");
      case PERIOD_M5:  return("M5");
      case PERIOD_M6:  return("M6");
      case PERIOD_M10: return("M10");
      case PERIOD_M12: return("M12");
      case PERIOD_M15: return("M15");
      case PERIOD_M20: return("M20");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H2:  return("H2");
      case PERIOD_H3:  return("H3");
      case PERIOD_H4:  return("H4");
      case PERIOD_H6:  return("H6");
      case PERIOD_H8:  return("H8");
      case PERIOD_H12: return("H12");
      case PERIOD_D1:  return("D1");
      case PERIOD_W1:  return("W1");
      case PERIOD_MN1: return("MN1");
     }
   return("?");
}

//+------------------------------------------------------------------+
bool IsBuyOrderType(const ENUM_ORDER_TYPE t)
{
   return(t == ORDER_TYPE_BUY ||
          t == ORDER_TYPE_BUY_LIMIT ||
          t == ORDER_TYPE_BUY_STOP ||
          t == ORDER_TYPE_BUY_STOP_LIMIT);
}

//+------------------------------------------------------------------+
double NormalizePrice(const double price)
{
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0)
      tick = _Point;
   return(NormalizeDouble(MathRound(price / tick) * tick, _Digits));
}

//+------------------------------------------------------------------+
double NormalizeLot(const double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minl = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxl = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0)
      step = 0.01;
   if(minl <= 0.0)
      minl = step;
   double v = MathFloor(lot / step + 1e-8) * step;
   if(v < minl)
      v = minl;
   if(maxl > 0.0 && v > maxl)
      v = maxl;
   const int digits = (step >= 1.0) ? 0 : (int)MathRound(-MathLog10(step));
   return(NormalizeDouble(v, MathMax(digits, 0)));
}

//+------------------------------------------------------------------+
string SideText(const int direction)
{
   return((direction > 0) ? "Buy" : "Sell");
}

//+------------------------------------------------------------------+
string GroupFromComment(const string comment)
{
   const int n = StringLen(comment);
   for(int i = 0; i < n - 1; i++)
     {
      const ushort c = StringGetCharacter(comment, i);
      const ushort d = StringGetCharacter(comment, i + 1);
      const bool letter = ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'));
      if(letter && d >= '0' && d <= '9')
         return(StringSubstr(comment, i, 1));
     }
   return("-");
}

//+------------------------------------------------------------------+
void NotifyNewPos1Orders(const LiveItem &items[])
{
   for(int gi = 0; gi < ArraySize(g_groups); gi++)
     {
      if(g_groups[gi].orderNotified || g_groups[gi].clExecuted)
         continue;

      int pos1Idx = -1;
      for(int i = 0; i < ArraySize(items); i++)
        {
         if(!items[i].parsed || items[i].ignored)
            continue;
         if(!ItemMatchesGroup(items[i], g_groups[gi]))
            continue;
         if(items[i].pac.position == 1)
           {
            pos1Idx = i;
            break;
           }
        }
      if(pos1Idx < 0)
         continue;

      const LiveItem pos1 = items[pos1Idx];
      const ENUM_ORDER_TYPE otype = (g_groups[gi].direction > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double pTp = 0;
      double pCl = 0;
      if(pos1.lot > 0.0 && pos1.price > 0.0)
        {
         if(pos1.tp > 0.0)
           {
            double p = 0;
            if(OrderCalcProfit(otype, _Symbol, pos1.lot, pos1.price, pos1.tp, p))
               pTp = p;
           }
         if(g_groups[gi].clPrice > 0.0)
           {
            double p = 0;
            if(OrderCalcProfit(otype, _Symbol, pos1.lot, pos1.price, g_groups[gi].clPrice, p))
               pCl = p;
           }
        }

      string cmtShow = pos1.comment;
      if(pos1.parsed)
         cmtShow = pos1.pac.groupCode +
                   IntegerToString(pos1.pac.layerCount) +
                   IntegerToString(pos1.pac.position) + "/" +
                   pos1.pac.tfText + "/" + pos1.pac.clText;

      NotifyInfo("Order " + _Symbol + " " + SideText(g_groups[gi].direction) + " " +
                 cmtShow + " [" + DoubleToString(pTp, 2) + "/" +
                 DoubleToString(MathAbs(pCl), 2) + "]",
                 false);
      g_groups[gi].orderNotified = true;
     }
}

//+------------------------------------------------------------------+
void LogPrint(const string msg)
{
   Print("[Panbes] ", msg);
}

//+------------------------------------------------------------------+
void LogAlert(const string msg)
{
   Print("[Panbes] ", msg);
   Alert("Panbes: ", msg);
   if(InpPushNotify)
      SendNotification("Panbes: " + msg);
}

//+------------------------------------------------------------------+
void NotifyInfo(const string msg, const bool doAlert)
{
   Print("[Panbes] ", msg);
   if(doAlert)
      Alert("Panbes: ", msg);
   if(InpPushNotify)
      SendNotification("Panbes: " + msg);
}

//+------------------------------------------------------------------+
bool TicketInList(const ulong ticket, const ulong &list[])
{
   for(int i = 0; i < ArraySize(list); i++)
     {
      if(list[i] == ticket)
         return(true);
     }
   return(false);
}

//+------------------------------------------------------------------+
void RememberTicket(const ulong ticket, ulong &list[])
{
   if(TicketInList(ticket, list))
      return;
   const int n = ArraySize(list);
   ArrayResize(list, n + 1);
   list[n] = ticket;
}

//+------------------------------------------------------------------+
bool DealProcessed(const ulong deal)
{
   return(TicketInList(deal, g_processedDeals));
}

//+------------------------------------------------------------------+
void MarkDealProcessed(const ulong deal)
{
   int n = ArraySize(g_processedDeals);
   if(n >= 500)
     {
      for(int i = 0; i < 400; i++)
         g_processedDeals[i] = g_processedDeals[i + 100];
      ArrayResize(g_processedDeals, 400);
      n = 400;
     }
   ArrayResize(g_processedDeals, n + 1);
   g_processedDeals[n] = deal;
}

//+------------------------------------------------------------------+
int FindGroupIndex(const string code)
{
   for(int i = 0; i < ArraySize(g_groups); i++)
     {
      if(g_groups[i].groupCode == code)
         return(i);
     }
   return(-1);
}

//+------------------------------------------------------------------+
int FindBatchIndex(const string code)
{
   for(int i = 0; i < ArraySize(g_tpBatches); i++)
     {
      if(g_tpBatches[i].groupCode == code)
         return(i);
     }
   return(-1);
}

//+------------------------------------------------------------------+
int FindSnapIndex(const ulong positionId)
{
   for(int i = 0; i < ArraySize(g_snaps); i++)
     {
      if(g_snaps[i].positionId == positionId)
         return(i);
     }
   return(-1);
}

//+------------------------------------------------------------------+
void UpsertPositionSnapshot(const ulong posTicket)
{
   if(posTicket == 0)
      return;
   if(!PositionSelectByTicket(posTicket))
      return;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return;

   Snapshot s;
   s.positionId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   s.ticket     = posTicket;
   s.comment    = PositionGetString(POSITION_COMMENT);
   s.entry      = PositionGetDouble(POSITION_PRICE_OPEN);
   s.sl         = PositionGetDouble(POSITION_SL);
   s.tp         = PositionGetDouble(POSITION_TP);
   s.lot        = PositionGetDouble(POSITION_VOLUME);
   s.isBuy      = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

   const int idx = FindSnapIndex(s.positionId);
   if(idx >= 0)
     {
      g_snaps[idx] = s;
      return;
     }
   const int n = ArraySize(g_snaps);
   ArrayResize(g_snaps, n + 1);
   g_snaps[n] = s;
}
//+------------------------------------------------------------------+
