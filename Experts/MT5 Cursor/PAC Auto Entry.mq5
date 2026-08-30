//+------------------------------------------------------------------+
//|                                               PAC Auto Entry.mq5 |
//|     PAC Auto Entry — Pivot + Base + Control + pending + CLCC     |
//|  Reentry setelah TP. CLCC close candle, bukan SL sentuh.         |
//+------------------------------------------------------------------+
#property copyright "PAC Auto Entry"
#property version   "1.01"
#property description "PAC Auto Entry — Pivot, Base, Control, pending, CLCC, reentry"

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| TYPES                                                            |
//+------------------------------------------------------------------+
enum ENUM_PIVOT_TYPE
  {
   PIVOT_BUY  = 1,
   PIVOT_SELL = -1
  };

enum ENUM_PIVOT_MARK
  {
   MARK_LOZENGE_SM = 115, // Belah ketupat kecil
   MARK_LOZENGE    = 116, // Belah ketupat
   MARK_DIAMOND    = 117, // Diamond
   MARK_DIAMOND_SM = 119, // Diamond kecil
   MARK_DOT        = 159, // Titik
   MARK_CIRCLE     = 108, // Lingkaran
   MARK_ARROW      = 233, // Panah atas/bawah
   MARK_TRIANGLE   = 241  // Segitiga atas/bawah
  };

enum ENUM_HOUR_FILTER_MODE
  {
   HOUR_FLATTEN_ALL      = 0, // Tutup semua posisi + hapus pending
   HOUR_CANCEL_PENDING   = 1, // Hanya hapus pending, biarkan posisi terbuka jalan
   HOUR_BLOCK_ENTRY_ONLY = 2, // Cuma blokir entry baru, biarkan semua yg sudah ada
  };

enum ENUM_DETECTION_TF
  {
   TF_AUTO = 0,           // Auto
   TF_M1   = PERIOD_M1,   // 1 Minute
   TF_M2   = PERIOD_M2,   // 2 Minutes
   TF_M3   = PERIOD_M3,   // 3 Minutes
   TF_M4   = PERIOD_M4,   // 4 Minutes
   TF_M5   = PERIOD_M5,   // 5 Minutes
   TF_M6   = PERIOD_M6,   // 6 Minutes
   TF_M10  = PERIOD_M10,  // 10 Minutes
   TF_M12  = PERIOD_M12,  // 12 Minutes
   TF_M15  = PERIOD_M15,  // 15 Minutes
   TF_M20  = PERIOD_M20,  // 20 Minutes
   TF_M30  = PERIOD_M30,  // 30 Minutes
   TF_H1   = PERIOD_H1,   // 1 Hour
   TF_H2   = PERIOD_H2,   // 2 Hours
   TF_H3   = PERIOD_H3,   // 3 Hours
   TF_H4   = PERIOD_H4,   // 4 Hours
   TF_H6   = PERIOD_H6,   // 6 Hours
   TF_H8   = PERIOD_H8,   // 8 Hours
   TF_H12  = PERIOD_H12,  // 12 Hours
   TF_D1   = PERIOD_D1,   // Daily
   TF_W1   = PERIOD_W1,   // Weekly
   TF_MN1  = PERIOD_MN1   // Monthly
  };

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "=== Deteksi ==="
input ENUM_DETECTION_TF InpDetectionTF = TF_AUTO;         // TF Pivot & Base
input int               InpLookback       = 500;             // Jml bar scan
input int               InpMaxBaseCandles = 10;              // Maks candle Base per zona
input ENUM_PIVOT_MARK   InpPivotSymbol = MARK_LOZENGE_SM; // Pivot - Style Tag
input int               InpGapPips     = 5;               // Pivot - Offset Tag (pips)
input color             InpPivotColor  = clrYellow;       // Pivot - Warna Tag
input color             InpBaseColor   = clrWhite;        // Base - Warna Candle
input color             InpSupportColor = clrForestGreen; // RBR - Warna Zona
input color             InpResistColor  = clrFireBrick;   // DBD - Warna Zona

input group "=== Area ==="
input int InpMaxAreaWidth = 600; // Jarak max Atap-Lantai (pips)
input int InpCLBuffer     = 80;  // Buffer CL (pips)
input int InpSLRatio      = 300; // Rasio SL-CL vs CL-TP (%)
input int InpLayerCount   = 3;   // Jumlah layer

input group "=== Order ==="
input bool   InpSendOrders        = true; // Kirim pending otomatis
input double InpLot               = 0.01; // Lot dasar (layer 1 / jauh dari CL)
input bool   InpLotStepUp         = true; // Lot bertingkat jika layer > 1 (terbesar dekat CL)
input int    InpMaxGroupsPerSide  = 1;    // Maks grup per arah (Buy/Sell)
input int    InpMaxPivotTouches   = 2;    // Maks sentuhan pivot (termasuk yg mengaktifkan)
input bool   InpAlertOnCL       = false; // Alert saat CLCC
input bool   InpAlertOnReentry  = false; // Alert saat reentry
input int    InpMaxReentry      = 3;     // Maks reentry per grup setelah TP

input group "=== News ==="
input bool InpNewsFilter     = true; // Filter berita USD high-impact Investing (hardcode Jan-Agu 2026)
input int  InpNewsMinsBefore = 60;   // Menit sebelum rilis
input int  InpNewsMinsAfter  = 60;   // Menit sesudah rilis

input group "=== Filter Jam ==="
input bool InpHourFilter = true; // Filter jam rawan rugi (WIB, hasil analisis backtest multi-run)
input ENUM_HOUR_FILTER_MODE InpHourFilterMode = HOUR_FLATTEN_ALL; // Aksi saat jendela jam aktif

//+------------------------------------------------------------------+
//| CONST                                                            |
//+------------------------------------------------------------------+
const string PREFIX_PB     = "PAC_PB_";
const string PREFIX_PS     = "PAC_PS_";
const string PREFIX_BASE   = "PAC_BASE_";
const string PREFIX_RBR    = "PAC_RBR_"; // sisa versi lama, dihapus saat init
const string PREFIX_DBD    = "PAC_DBD_";
const string PREFIX_SUP    = "PAC_SUP_";
const string PREFIX_RES    = "PAC_RES_";
const string PREFIX_ATAP   = "PAC_ATAP";
const string PREFIX_LANTAI = "PAC_LANTAI";
const string PREFIX_LV     = "PAC_LV_";
const string PREFIX_NEWS   = "PAC_NEWS_";
const color  NEWS_CLR_ON   = clrOrangeRed;      // jendela aktif
const color  NEWS_CLR_OFF  = clrMediumSeaGreen; // jendela inaktif
const string PREFIX_HOUR   = "PAC_HOUR_";
const color  HOUR_CLR_ON   = clrDeepSkyBlue;    // jendela jam mulai
const color  HOUR_CLR_OFF  = clrSlateGray;      // jendela jam berakhir
const double BASE_BODY_RATIO  = 0.5; // |Close-Open| â‰¤ rasio Ã— (High-Low)
const int    IMPULSE_BODY_PCT = 50;  // Body minimal rally/drop (% dari High-Low)
const long   InpMagic         = 999; // Magic Number EA PAC (bukan 0)
const int    InpDeviation     = 30;
const int    InpTpWindowMs    = 1000;

struct Pivot
  {
   datetime        time;
   double          open;
   double          high;
   double          low;
   double          close;
   ENUM_PIVOT_TYPE type;
   datetime        confirm1;
   datetime        confirm2;
  };

struct Base
  {
   datetime time;
   double   open;
   double   high;
   double   low;
   double   close;
  };

struct SrZone
  {
   datetime left;
   datetime right;
   datetime lastBase;
   double   high;
   double   low;
   bool     isSupport;
   bool     isControl;
   bool     isWeak;
   datetime pivotTime;
   int      pivotTouches;
  };

struct PacCmt
  {
   string          groupCode;
   bool            isBuy;
   bool            paired;
   int             layerCount;
   int             position;
   ENUM_TIMEFRAMES timeframe;
   double          clPrice;
   string          tfText;
   string          stamp;
  };

struct LiveItem
  {
   ulong           ticket;
   ulong           positionId;
   bool            isPosition;
   string          comment;
   PacCmt          pac;
   bool            parsed;
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
   int             layerCount;
   int             direction;
   datetime        lastCheckedBarTime;
   int             reentryCount;
   bool            clExecuted;
   datetime        startedAt;
  };

struct Snapshot
  {
   ulong  positionId;
   ulong  ticket;
   string comment;
   double entry;
   double sl;
   double tp;
   double lot;
   bool   isBuy;
  };

struct TpSlot
  {
   string comment;
   double entry;
   double sl;
   double tp;
   double lot;
   bool   isBuy;
  };

struct TpBatch
  {
   string groupCode;
   ulong  windowStartMs;
   TpSlot slots[];
  };

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
Pivot            g_pivots[];
Base             g_bases[];
SrZone           g_zones[];
datetime         g_lastBarTime = 0;
ENUM_TIMEFRAMES  g_usedTF      = PERIOD_CURRENT;
CTrade           g_trade;
PacGroup         g_groups[];
Snapshot         g_snaps[];
TpBatch          g_tpBatches[];
ulong            g_processedDeals[];
bool             g_inRefresh = false;
string           g_clccGroup = "";
double           g_clccCl[];
bool             g_clccBuy[];
string           g_lastNewsName = "";
string           g_lastHourFilterLabel = "";
datetime         g_newsUtc[];
string           g_newsName[];
datetime         g_newsCacheFrom  = 0;
datetime         g_newsCacheUntil = 0;
bool             g_newsCacheIn    = false;
string           g_newsCacheName  = "";

//+------------------------------------------------------------------+
ENUM_TIMEFRAMES DetectionTF()
  {
   if(InpDetectionTF == TF_AUTO)
      return((ENUM_TIMEFRAMES)Period());
   return((ENUM_TIMEFRAMES)InpDetectionTF);
  }

//+------------------------------------------------------------------+
bool ChartVisualsOn()
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
      return(false);
   if(MQLInfoInteger(MQL_TESTER) != 0 && MQLInfoInteger(MQL_VISUAL_MODE) == 0)
      return(false);
   return(true);
  }

//+------------------------------------------------------------------+
//| News USD high-impact Investing.com (filter High Volatility, USD).|
//| Jam rilis UTC. Filter & garis chart sama: jam server HFM.        |
//| Sumber: Investing calendar 1 Jan-31 Agu 2026 + BLS/BEA/Fed.      |
//+------------------------------------------------------------------+
int NewsCount()
  {
   return(ArraySize(g_newsUtc));
  }

//+------------------------------------------------------------------+
datetime NewsTimeUtc(const int i)
  {
   if(i < 0 || i >= ArraySize(g_newsUtc))
      return(0);
   return(g_newsUtc[i]);
  }

//+------------------------------------------------------------------+
string NewsLabel(const int i)
  {
   if(i < 0 || i >= ArraySize(g_newsName))
      return("");
   return(g_newsName[i]);
  }

//+------------------------------------------------------------------+
string NewsMajorText(const int i)
  {
   const string n = NewsLabel(i);
   if(n == "")
      return("");
   return("Major: " + n);
  }

//+------------------------------------------------------------------+
void AddNews(const datetime t, const string name)
  {
   if(t <= 0 || name == "")
      return;
   const int n = ArraySize(g_newsUtc);
   ArrayResize(g_newsUtc, n + 1);
   ArrayResize(g_newsName, n + 1);
   g_newsUtc[n]  = t;
   g_newsName[n] = name;
  }

//+------------------------------------------------------------------+
void InvalidateNewsCache()
  {
   g_newsCacheFrom  = 0;
   g_newsCacheUntil = 0;
   g_newsCacheIn    = false;
   g_newsCacheName  = "";
  }

//+------------------------------------------------------------------+
void RefreshNewsCache(const datetime now)
  {
   g_newsCacheFrom  = now;
   g_newsCacheUntil = now + 86400;
   g_newsCacheIn    = false;
   g_newsCacheName  = "";
   const int before = MathMax(InpNewsMinsBefore, 0) * 60;
   const int after  = MathMax(InpNewsMinsAfter, 0) * 60;
   const int n = NewsCount();
   datetime nextOn = 0;
   for(int i = 0; i < n; i++)
     {
      const datetime utc = NewsTimeUtc(i);
      if(utc <= 0)
         continue;
      const datetime tOn  = UtcToHfmChart(utc - before);
      const datetime tOff = UtcToHfmChart(utc + after);
      if(now >= tOn && now <= tOff)
        {
         g_newsCacheUntil = tOff + 1;
         g_newsCacheIn    = true;
         g_newsCacheName  = NewsMajorText(i);
         return;
        }
      if(tOn > now && (nextOn == 0 || tOn < nextOn))
         nextOn = tOn;
     }
   if(nextOn > now)
      g_newsCacheUntil = nextOn;
  }

//+------------------------------------------------------------------+
void InitNewsCalendar()
  {
   InvalidateNewsCache();
   ArrayResize(g_newsUtc, 0);
   ArrayResize(g_newsName, 0);
   AddNews(D'2026.01.02 14:45:00', "S&P Mfg PMI");
   AddNews(D'2026.01.05 15:00:00', "ISM Mfg");
   AddNews(D'2026.01.06 14:45:00', "S&P Svc PMI");
   AddNews(D'2026.01.07 13:15:00', "ADP");
   AddNews(D'2026.01.07 15:00:00', "ISM Svc");
   AddNews(D'2026.01.07 15:30:00', "Oil Inv");
   AddNews(D'2026.01.08 13:30:00', "Claims");
   AddNews(D'2026.01.09 13:30:00', "NFP");
   AddNews(D'2026.01.12 18:00:00', "10Y Auction");
   AddNews(D'2026.01.13 13:30:00', "CPI");
   AddNews(D'2026.01.13 14:59:00', "New Homes");
   AddNews(D'2026.01.13 15:00:00', "New Homes");
   AddNews(D'2026.01.13 18:00:00', "30Y Auction");
   AddNews(D'2026.01.13 19:00:00', "Trump");
   AddNews(D'2026.01.14 13:29:00', "PPI");
   AddNews(D'2026.01.14 13:30:00', "Retail Sales");
   AddNews(D'2026.01.14 15:00:00', "Existing Homes");
   AddNews(D'2026.01.14 15:30:00', "Oil Inv");
   AddNews(D'2026.01.15 13:30:00', "Claims");
   AddNews(D'2026.01.21 13:30:00', "Trump");
   AddNews(D'2026.01.22 13:30:00', "GDP");
   AddNews(D'2026.01.22 14:59:00', "PCE");
   AddNews(D'2026.01.22 15:00:00', "PCE");
   AddNews(D'2026.01.22 17:00:00', "Oil Inv");
   AddNews(D'2026.01.23 14:45:00', "S&P Mfg PMI");
   AddNews(D'2026.01.26 13:30:00', "Durable Goods");
   AddNews(D'2026.01.27 15:00:00', "CB Confidence");
   AddNews(D'2026.01.27 21:00:00', "Trump");
   AddNews(D'2026.01.28 15:30:00', "Oil Inv");
   AddNews(D'2026.01.28 19:00:00', "FOMC");
   AddNews(D'2026.01.28 19:30:00', "FOMC Press");
   AddNews(D'2026.01.29 13:30:00', "Claims");
   AddNews(D'2026.01.29 21:30:00', "Trump");
   AddNews(D'2026.01.30 13:30:00', "PPI");
   AddNews(D'2026.01.30 14:45:00', "Chicago PMI");
   AddNews(D'2026.02.02 14:45:00', "S&P Mfg PMI");
   AddNews(D'2026.02.02 15:00:00', "ISM Mfg");
   AddNews(D'2026.02.04 13:15:00', "ADP");
   AddNews(D'2026.02.04 14:45:00', "S&P Svc PMI");
   AddNews(D'2026.02.04 15:00:00', "ISM Svc");
   AddNews(D'2026.02.04 15:30:00', "Oil Inv");
   AddNews(D'2026.02.05 13:30:00', "Claims");
   AddNews(D'2026.02.05 15:00:00', "JOLTS");
   AddNews(D'2026.02.06 00:00:00', "Trump");
   AddNews(D'2026.02.10 13:30:00', "Retail Sales");
   AddNews(D'2026.02.11 13:30:00', "NFP");
   AddNews(D'2026.02.11 15:30:00', "Oil Inv");
   AddNews(D'2026.02.11 18:00:00', "10Y Auction");
   AddNews(D'2026.02.12 13:30:00', "Claims");
   AddNews(D'2026.02.12 15:00:00', "Existing Homes");
   AddNews(D'2026.02.12 18:00:00', "30Y Auction");
   AddNews(D'2026.02.13 13:30:00', "CPI");
   AddNews(D'2026.02.18 13:30:00', "Durable Goods");
   AddNews(D'2026.02.18 19:00:00', "FOMC Minutes");
   AddNews(D'2026.02.19 13:30:00', "Claims");
   AddNews(D'2026.02.19 17:00:00', "Oil Inv");
   AddNews(D'2026.02.20 13:30:00', "PCE");
   AddNews(D'2026.02.20 14:45:00', "S&P Mfg PMI");
   AddNews(D'2026.02.20 14:59:00', "New Homes");
   AddNews(D'2026.02.20 15:00:00', "New Homes");
   AddNews(D'2026.02.20 17:45:00', "Trump");
   AddNews(D'2026.02.24 15:00:00', "CB Confidence");
   AddNews(D'2026.02.25 02:00:00', "Trump");
   AddNews(D'2026.02.25 15:30:00', "Oil Inv");
   AddNews(D'2026.02.26 13:30:00', "Claims");
   AddNews(D'2026.02.27 13:30:00', "PPI");
   AddNews(D'2026.02.27 14:45:00', "Chicago PMI");
   AddNews(D'2026.03.02 14:45:00', "S&P Mfg PMI");
   AddNews(D'2026.03.02 15:00:00', "ISM Mfg");
   AddNews(D'2026.03.02 16:00:00', "Trump");
   AddNews(D'2026.03.04 13:15:00', "ADP");
   AddNews(D'2026.03.04 14:45:00', "S&P Svc PMI");
   AddNews(D'2026.03.04 15:00:00', "ISM Svc");
   AddNews(D'2026.03.04 15:30:00', "Oil Inv");
   AddNews(D'2026.03.05 13:30:00', "Claims");
   AddNews(D'2026.03.06 13:30:00', "NFP");
   AddNews(D'2026.03.10 14:00:00', "Existing Homes");
   AddNews(D'2026.03.11 12:30:00', "CPI");
   AddNews(D'2026.03.11 14:30:00', "Oil Inv");
   AddNews(D'2026.03.11 17:00:00', "10Y Auction");
   AddNews(D'2026.03.11 20:25:00', "Trump");
   AddNews(D'2026.03.12 12:30:00', "Claims");
   AddNews(D'2026.03.12 17:00:00', "30Y Auction");
   AddNews(D'2026.03.13 12:30:00', "PCE");
   AddNews(D'2026.03.13 14:00:00', "JOLTS");
   AddNews(D'2026.03.16 15:30:00', "Trump");
   AddNews(D'2026.03.17 15:30:00', "Trump");
   AddNews(D'2026.03.18 12:30:00', "PPI");
   AddNews(D'2026.03.18 14:30:00', "Oil Inv");
   AddNews(D'2026.03.18 18:00:00', "FOMC");
   AddNews(D'2026.03.18 18:30:00', "FOMC Press");
   AddNews(D'2026.03.19 12:30:00', "Claims");
   AddNews(D'2026.03.19 14:00:00', "New Homes");
   AddNews(D'2026.03.21 14:30:00', "Fed Chair");
   AddNews(D'2026.03.23 13:30:00', "Trump");
   AddNews(D'2026.03.24 13:45:00', "S&P Mfg PMI");
   AddNews(D'2026.03.25 14:30:00', "Oil Inv");
   AddNews(D'2026.03.25 23:20:00', "Trump");
   AddNews(D'2026.03.26 12:30:00', "Claims");
   AddNews(D'2026.03.26 19:00:00', "Trump");
   AddNews(D'2026.03.26 20:00:00', "Trump");
   AddNews(D'2026.03.27 21:30:00', "Trump");
   AddNews(D'2026.03.29 22:30:00', "Trump");
   AddNews(D'2026.03.30 14:30:00', "Fed Chair");
   AddNews(D'2026.03.31 13:45:00', "Chicago PMI");
   AddNews(D'2026.03.31 14:00:00', "JOLTS");
   AddNews(D'2026.04.01 12:15:00', "ADP");
   AddNews(D'2026.04.01 12:30:00', "Retail Sales");
   AddNews(D'2026.04.01 13:45:00', "S&P Mfg PMI");
   AddNews(D'2026.04.01 14:00:00', "ISM Mfg");
   AddNews(D'2026.04.01 14:30:00', "Oil Inv");
   AddNews(D'2026.04.02 01:00:00', "Trump");
   AddNews(D'2026.04.02 12:30:00', "Claims");
   AddNews(D'2026.04.03 12:30:00', "NFP");
   AddNews(D'2026.04.03 13:45:00', "S&P Svc PMI");
   AddNews(D'2026.04.06 14:00:00', "ISM Svc");
   AddNews(D'2026.04.06 17:00:00', "Trump");
   AddNews(D'2026.04.07 12:30:00', "Durable Goods");
   AddNews(D'2026.04.08 14:30:00', "Oil Inv");
   AddNews(D'2026.04.08 17:00:00', "10Y Auction");
   AddNews(D'2026.04.08 18:00:00', "FOMC Minutes");
   AddNews(D'2026.04.09 12:30:00', "PCE");
   AddNews(D'2026.04.09 17:00:00', "30Y Auction");
   AddNews(D'2026.04.10 12:30:00', "CPI");
   AddNews(D'2026.04.13 14:00:00', "Existing Homes");
   AddNews(D'2026.04.14 12:30:00', "PPI");
   AddNews(D'2026.04.15 10:00:00', "Trump");
   AddNews(D'2026.04.15 14:30:00', "Oil Inv");
   AddNews(D'2026.04.16 12:30:00', "Claims");
   AddNews(D'2026.04.16 23:00:00', "Trump");
   AddNews(D'2026.04.17 18:00:00', "Trump");
   AddNews(D'2026.04.21 12:30:00', "Retail Sales");
   AddNews(D'2026.04.22 14:30:00', "Oil Inv");
   AddNews(D'2026.04.23 12:30:00', "Claims");
   AddNews(D'2026.04.23 13:45:00', "S&P Mfg PMI");
   AddNews(D'2026.04.25 16:00:00', "Trump");
   AddNews(D'2026.04.26 02:45:00', "Trump");
   AddNews(D'2026.04.26 23:00:00', "Trump");
   AddNews(D'2026.04.28 14:00:00', "CB Confidence");
   AddNews(D'2026.04.29 12:30:00', "Durable Goods");
   AddNews(D'2026.04.29 14:30:00', "Oil Inv");
   AddNews(D'2026.04.29 18:00:00', "FOMC");
   AddNews(D'2026.04.29 18:30:00', "FOMC Press");
   AddNews(D'2026.04.30 12:30:00', "PCE");
   AddNews(D'2026.04.30 13:45:00', "Chicago PMI");
   AddNews(D'2026.05.01 13:45:00', "S&P Mfg PMI");
   AddNews(D'2026.05.01 14:00:00', "ISM Mfg");
   AddNews(D'2026.05.01 19:00:00', "Trump");
   AddNews(D'2026.05.05 13:45:00', "S&P Svc PMI");
   AddNews(D'2026.05.05 13:59:00', "New Homes");
   AddNews(D'2026.05.05 14:00:00', "ISM Svc");
   AddNews(D'2026.05.06 12:15:00', "ADP");
   AddNews(D'2026.05.06 14:30:00', "Oil Inv");
   AddNews(D'2026.05.07 12:30:00', "Claims");
   AddNews(D'2026.05.08 12:30:00', "NFP");
   AddNews(D'2026.05.08 16:00:00', "Trump");
   AddNews(D'2026.05.11 14:00:00', "Existing Homes");
   AddNews(D'2026.05.12 12:30:00', "CPI");
   AddNews(D'2026.05.12 17:00:00', "10Y Auction");
   AddNews(D'2026.05.13 12:30:00', "PPI");
   AddNews(D'2026.05.13 14:30:00', "Oil Inv");
   AddNews(D'2026.05.13 17:00:00', "30Y Auction");
   AddNews(D'2026.05.14 12:30:00', "Retail Sales");
   AddNews(D'2026.05.20 14:30:00', "Oil Inv");
   AddNews(D'2026.05.20 18:00:00', "FOMC Minutes");
   AddNews(D'2026.05.21 12:30:00', "Claims");
   AddNews(D'2026.05.21 13:45:00', "S&P Mfg PMI");
   AddNews(D'2026.05.26 14:00:00', "CB Confidence");
   AddNews(D'2026.05.28 12:30:00', "PCE");
   AddNews(D'2026.05.28 14:00:00', "New Homes");
   AddNews(D'2026.05.28 16:00:00', "Oil Inv");
   AddNews(D'2026.05.29 13:45:00', "Chicago PMI");
   AddNews(D'2026.06.01 00:30:00', "Fed Chair");
   AddNews(D'2026.06.01 13:45:00', "S&P Mfg PMI");
   AddNews(D'2026.06.01 14:00:00', "ISM Mfg");
   AddNews(D'2026.06.02 14:00:00', "JOLTS");
   AddNews(D'2026.06.03 12:15:00', "ADP");
   AddNews(D'2026.06.03 13:45:00', "S&P Svc PMI");
   AddNews(D'2026.06.03 14:00:00', "ISM Svc");
   AddNews(D'2026.06.03 14:30:00', "Oil Inv");
   AddNews(D'2026.06.04 12:30:00', "Claims");
   AddNews(D'2026.06.04 19:00:00', "Trump");
   AddNews(D'2026.06.05 12:30:00', "NFP");
   AddNews(D'2026.06.09 14:00:00', "Existing Homes");
   AddNews(D'2026.06.10 12:30:00', "CPI");
   AddNews(D'2026.06.10 14:30:00', "Oil Inv");
   AddNews(D'2026.06.10 17:00:00', "10Y Auction");
   AddNews(D'2026.06.11 12:30:00', "PPI");
   AddNews(D'2026.06.17 12:30:00', "Retail Sales");
   AddNews(D'2026.06.17 14:30:00', "Oil Inv");
   AddNews(D'2026.06.17 14:45:00', "Trump");
   AddNews(D'2026.06.17 18:00:00', "FOMC");
   AddNews(D'2026.06.17 18:30:00', "FOMC Press");
   AddNews(D'2026.06.18 12:30:00', "Claims");
   AddNews(D'2026.06.23 13:45:00', "S&P Mfg PMI");
   AddNews(D'2026.06.23 18:05:00', "Trump");
   AddNews(D'2026.06.24 14:00:00', "New Homes");
   AddNews(D'2026.06.24 14:30:00', "Oil Inv");
   AddNews(D'2026.06.25 00:30:00', "Trump");
   AddNews(D'2026.06.25 12:30:00', "PCE");
   AddNews(D'2026.06.26 17:30:00', "Trump");
   AddNews(D'2026.06.30 13:45:00', "Chicago PMI");
   AddNews(D'2026.06.30 14:00:00', "JOLTS");
   AddNews(D'2026.07.01 12:15:00', "ADP");
   AddNews(D'2026.07.01 13:00:00', "Fed Chair");
   AddNews(D'2026.07.01 13:45:00', "S&P Mfg PMI");
   AddNews(D'2026.07.01 14:00:00', "ISM Mfg");
   AddNews(D'2026.07.01 14:30:00', "Oil Inv");
   AddNews(D'2026.07.01 19:15:00', "Trump");
   AddNews(D'2026.07.02 12:30:00', "NFP");
   AddNews(D'2026.07.06 13:45:00', "S&P Svc PMI");
   AddNews(D'2026.07.06 14:00:00', "ISM Svc");
   AddNews(D'2026.07.08 14:30:00', "Oil Inv");
   AddNews(D'2026.07.08 17:00:00', "10Y Auction");
   AddNews(D'2026.07.08 18:00:00', "FOMC Minutes");
   AddNews(D'2026.07.09 12:30:00', "Claims");
   AddNews(D'2026.07.09 14:00:00', "Existing Homes");
   AddNews(D'2026.07.09 17:01:00', "30Y Auction");
   AddNews(D'2026.07.10 15:00:00', "Fed Monetary Policy Report");
   AddNews(D'2026.07.14 12:30:00', "CPI");
   AddNews(D'2026.07.15 12:30:00', "PPI");
   AddNews(D'2026.07.15 14:30:00', "Oil Inv");
   AddNews(D'2026.07.16 12:30:00', "Retail Sales");
   AddNews(D'2026.07.17 01:00:00', "Trump");
   AddNews(D'2026.07.22 14:30:00', "Oil Inv");
   AddNews(D'2026.07.22 19:00:00', "Trump");
   AddNews(D'2026.07.23 12:30:00', "Claims");
   AddNews(D'2026.07.24 13:45:00', "S&P Mfg PMI");
   AddNews(D'2026.07.24 14:00:00', "New Homes");
   AddNews(D'2026.07.25 00:55:00', "Trump");
   AddNews(D'2026.07.27 12:30:00', "Durable Goods");
   AddNews(D'2026.07.27 18:50:00', "Trump");
   AddNews(D'2026.07.28 14:00:00', "CB Confidence");
   AddNews(D'2026.07.29 14:30:00', "Oil Inv");
   AddNews(D'2026.07.29 18:00:00', "FOMC");
   AddNews(D'2026.07.29 18:30:00', "FOMC Press");
   AddNews(D'2026.07.30 12:30:00', "PCE");
   AddNews(D'2026.07.31 13:45:00', "Chicago PMI");
   AddNews(D'2026.08.03 13:45:00', "S&P Mfg PMI");
   AddNews(D'2026.08.03 14:00:00', "ISM Mfg");
   AddNews(D'2026.08.04 14:00:00', "JOLTS");
   AddNews(D'2026.08.05 12:15:00', "ADP");
   AddNews(D'2026.08.05 13:45:00', "S&P Svc PMI");
   AddNews(D'2026.08.05 14:00:00', "ISM Svc");
   AddNews(D'2026.08.05 14:30:00', "Oil Inv");
   AddNews(D'2026.08.05 20:30:00', "Trump");
   AddNews(D'2026.08.06 12:30:00', "Claims");
   AddNews(D'2026.08.07 12:30:00', "NFP");
   AddNews(D'2026.08.11 14:00:00', "Existing Homes");
   AddNews(D'2026.08.12 12:30:00', "CPI");
   AddNews(D'2026.08.12 14:30:00', "Oil Inv");
   AddNews(D'2026.08.12 17:00:00', "10Y Auction");
   AddNews(D'2026.08.13 12:30:00', "PPI");
   AddNews(D'2026.08.13 17:00:00', "30Y Auction");
   AddNews(D'2026.08.14 12:30:00', "Retail Sales");
   AddNews(D'2026.08.14 19:00:00', "Trump");
   AddNews(D'2026.08.19 14:30:00', "Oil Inv");
   AddNews(D'2026.08.19 18:00:00', "FOMC Minutes");
   AddNews(D'2026.08.19 18:30:00', "Trump");
   AddNews(D'2026.08.20 12:30:00', "Claims");
   AddNews(D'2026.08.21 13:45:00', "S&P Mfg PMI");
   AddNews(D'2026.08.21 23:00:00', "Trump");
   AddNews(D'2026.08.25 14:00:00', "CB Confidence");
   AddNews(D'2026.08.26 12:30:00', "PCE");
   AddNews(D'2026.08.26 14:30:00', "Oil Inv");
   AddNews(D'2026.08.27 12:30:00', "Claims");
   AddNews(D'2026.08.28 13:45:00', "Chicago PMI");
   AddNews(D'2026.08.28 14:00:00', "Fed Chair");
   AddNews(D'2026.08.31 13:45:00', "Chicago PMI");
  }

//+------------------------------------------------------------------+
datetime LastSundayOfMonth(const int year, const int month)
  {
   MqlDateTime dt;
   ZeroMemory(dt);
   if(month == 12)
     {
      dt.year = year + 1;
      dt.mon  = 1;
     }
   else
     {
      dt.year = year;
      dt.mon  = month + 1;
     }
   dt.day = 1;
   datetime t = StructToTime(dt) - 86400;
   TimeToStruct(t, dt);
   while(dt.day_of_week != 0)
     {
      t -= 86400;
      TimeToStruct(t, dt);
     }
   return(t);
  }

//+------------------------------------------------------------------+
//| Offset jam server HFM vs UTC pada timestamp UTC.                 |
//+------------------------------------------------------------------+
int HfmOffsetHours(const datetime utc)
  {
   if(utc <= 0)
      return(2);
   MqlDateTime dt;
   TimeToStruct(utc, dt);
   const datetime dstOn  = LastSundayOfMonth(dt.year, 3)  + 3600;
   const datetime dstOff = LastSundayOfMonth(dt.year, 10) + 3600;
   if(utc >= dstOn && utc < dstOff)
      return(3);
   return(2);
  }

//+------------------------------------------------------------------+
datetime UtcToHfmChart(const datetime utc)
  {
   if(utc <= 0)
      return(0);
   return(utc + (datetime)HfmOffsetHours(utc) * 3600);
  }

//+------------------------------------------------------------------+
//| Tebak offset HFM (2/3) dari waktu SERVER (kebalikan dari fungsi   |
//| di atas yang mulai dari UTC). Cuma ada 2 kandidat offset.         |
//+------------------------------------------------------------------+
int HfmOffsetHoursFromServer(const datetime serverTime)
  {
   if(HfmOffsetHours(serverTime - 2 * 3600) == 2)
      return(2);
   if(HfmOffsetHours(serverTime - 3 * 3600) == 3)
      return(3);
   return(2);
  }

//+------------------------------------------------------------------+
datetime ServerToUtc(const datetime serverTime)
  {
   if(serverTime <= 0)
      return(0);
   return(serverTime - (datetime)HfmOffsetHoursFromServer(serverTime) * 3600);
  }

//+------------------------------------------------------------------+
//| Jendela jam rawan rugi (WIB, UTC+7 tetap tanpa DST). Hasil        |
//| pemetaan jam-open per 15 menit dari 4 run backtest terverifikasi  |
//| (Jan-Jul 2026, XAUUSD M5) — lihat catatan analisis untuk detail.  |
//+------------------------------------------------------------------+
struct HourFilterWindow
  {
   int    startMin; // menit sejak 00:00 WIB
   int    endMin;   // inklusif
   string label;
  };

HourFilterWindow g_hourWindows[] =
  {
   { 5 * 60 + 15,  5 * 60 + 59, "05:15-05:59 WIB" },
   { 8 * 60 +  0,  8 * 60 + 44, "08:00-08:44 WIB" },
   {18 * 60 +  0, 18 * 60 + 14, "18:00-18:14 WIB" },
   {21 * 60 +  0, 21 * 60 + 14, "21:00-21:14 WIB" },
   {21 * 60 + 30, 21 * 60 + 44, "21:30-21:44 WIB" },
  };

//+------------------------------------------------------------------+
bool InHourFilterWindow(string &labelOut)
  {
   labelOut = "";
   if(!InpHourFilter)
      return(false);
   const datetime now = TimeCurrent();
   if(now <= 0)
      return(false);
   const datetime utc = ServerToUtc(now);
   const datetime wib = utc + 7 * 3600;
   MqlDateTime dt;
   TimeToStruct(wib, dt);
   const int mins = dt.hour * 60 + dt.min;
   const int n = ArraySize(g_hourWindows);
   for(int i = 0; i < n; i++)
     {
      if(mins >= g_hourWindows[i].startMin && mins <= g_hourWindows[i].endMin)
        {
         labelOut = g_hourWindows[i].label;
         return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| WIB (UTC+7 tetap) -> waktu server HFM, buat gambar garis chart.  |
//+------------------------------------------------------------------+
datetime WibToServer(const datetime wib)
  {
   if(wib <= 0)
      return(0);
   return(UtcToHfmChart(wib - 7 * 3600));
  }

//+------------------------------------------------------------------+
bool InNewsWindow(string &nameOut)
  {
   nameOut = "";
   if(!InpNewsFilter)
      return(false);
   const datetime now = TimeCurrent();
   if(now <= 0)
      return(false);
   if(g_newsCacheUntil <= 0 || now < g_newsCacheFrom || now >= g_newsCacheUntil)
      RefreshNewsCache(now);
   nameOut = g_newsCacheName;
   return(g_newsCacheIn);
  }

//+------------------------------------------------------------------+
void CreateNewsVLine(const string name, const datetime t, const color clr,
                     const ENUM_LINE_STYLE style, const string tip)
  {
   if(t <= 0)
      return;
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_VLINE, 0, t, 0))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
  }

//+------------------------------------------------------------------+
double NewsLabelPrice(const datetime t)
  {
   if(t > 0)
     {
      const int sh = iBarShift(_Symbol, PERIOD_CURRENT, t, false);
      if(sh >= 0)
        {
         const double h = iHigh(_Symbol, PERIOD_CURRENT, sh);
         if(h > 0.0)
            return(h);
        }
     }
   const double pmax = ChartGetDouble(0, CHART_PRICE_MAX);
   if(pmax > 0.0)
      return(pmax);
   return(SymbolInfoDouble(_Symbol, SYMBOL_BID));
  }

//+------------------------------------------------------------------+
void CreateNewsLabel(const string name, const datetime t, const string text)
  {
   if(t <= 0 || text == "")
      return;
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, NewsLabelPrice(t)))
      return;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_COLOR, NEWS_CLR_ON);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, text);
  }

//+------------------------------------------------------------------+
void DeleteNewsMarks()
  {
   ObjectsDeleteAll(0, PREFIX_NEWS);
  }

//+------------------------------------------------------------------+
void DrawNewsMarks()
  {
   DeleteNewsMarks();
   if(!InpNewsFilter || !ChartVisualsOn())
      return;
   const int before = MathMax(InpNewsMinsBefore, 0) * 60;
   const int after  = MathMax(InpNewsMinsAfter, 0) * 60;
   const int n = NewsCount();
   for(int i = 0; i < n; i++)
     {
      const datetime utc = NewsTimeUtc(i);
      if(utc <= 0)
         continue;
      const string major = NewsMajorText(i);
      const datetime tRel = UtcToHfmChart(utc);
      const datetime tOn  = UtcToHfmChart(utc - before);
      const datetime tOff = UtcToHfmChart(utc + after);
      const string id = IntegerToString(i);
      CreateNewsVLine(PREFIX_NEWS + "ON_" + id, tOn, NEWS_CLR_ON, STYLE_DASH,
                      major + " | jendela aktif");
      CreateNewsVLine(PREFIX_NEWS + "OFF_" + id, tOff, NEWS_CLR_OFF, STYLE_DOT,
                      major + " | jendela inaktif");
      CreateNewsLabel(PREFIX_NEWS + "LB_" + id, tRel, major);
     }
  }

//+------------------------------------------------------------------+
void DeleteHourMarks()
  {
   ObjectsDeleteAll(0, PREFIX_HOUR);
  }

//+------------------------------------------------------------------+
//| Gambar garis vertikal utk tiap jendela filter jam, diulang tiap  |
//| hari WIB dari bar tertua yang termuat sampai 7 hari ke depan.    |
//+------------------------------------------------------------------+
void DrawHourMarks()
  {
   DeleteHourMarks();
   if(!InpHourFilter || !ChartVisualsOn())
      return;
   const int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   if(totalBars <= 1)
      return;
   const datetime rangeStartServer = iTime(_Symbol, PERIOD_CURRENT, totalBars - 1);
   const datetime rangeEndServer   = TimeCurrent() + 7 * 86400;
   if(rangeStartServer <= 0 || rangeEndServer <= rangeStartServer)
      return;

   datetime wibStart = ServerToUtc(rangeStartServer) + 7 * 3600;
   const datetime wibEnd = ServerToUtc(rangeEndServer) + 7 * 3600;
   wibStart -= (wibStart % 86400); // turunkan ke tengah malam WIB

   int idx = 0;
   const int nWin = ArraySize(g_hourWindows);
   for(datetime dayWib = wibStart; dayWib <= wibEnd; dayWib += 86400)
     {
      for(int w = 0; w < nWin; w++)
        {
         const datetime tOnWib  = dayWib + g_hourWindows[w].startMin * 60;
         const datetime tOffWib = dayWib + g_hourWindows[w].endMin   * 60 + 60;
         const datetime tOnServer  = WibToServer(tOnWib);
         const datetime tOffServer = WibToServer(tOffWib);
         const string id = IntegerToString(idx++);
         CreateNewsVLine(PREFIX_HOUR + "ON_" + id, tOnServer, HOUR_CLR_ON, STYLE_DASH,
                         g_hourWindows[w].label + " | jendela jam mulai");
         CreateNewsVLine(PREFIX_HOUR + "OFF_" + id, tOffServer, HOUR_CLR_OFF, STYLE_DOT,
                         g_hourWindows[w].label + " | jendela jam berakhir");
        }
     }
  }

//+------------------------------------------------------------------+
void CancelNewsPendings()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      const string cmt = OrderGetString(ORDER_COMMENT);
      if(g_trade.OrderDelete(ticket) && TradeOk())
         Print("PAC news: hapus pending ", cmt);
     }
  }

//+------------------------------------------------------------------+
void CloseNewsPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      const string cmt = PositionGetString(POSITION_COMMENT);
      if(g_trade.PositionClose(ticket) && TradeOk())
         Print("PAC news: tutup posisi #", ticket, " ", cmt);
      else
         Print("PAC news: gagal tutup #", ticket, " ret=",
               g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
void FlattenNewsExposure()
  {
   ArrayResize(g_tpBatches, 0);
   CloseNewsPositions();
   CancelNewsPendings();
  }

//+------------------------------------------------------------------+
void DeleteMarks()
  {
   ObjectsDeleteAll(0, PREFIX_PB);
   ObjectsDeleteAll(0, PREFIX_PS);
   ObjectsDeleteAll(0, PREFIX_BASE);
   ObjectsDeleteAll(0, PREFIX_RBR);
   ObjectsDeleteAll(0, PREFIX_DBD);
   ObjectsDeleteAll(0, PREFIX_SUP);
   ObjectsDeleteAll(0, PREFIX_RES);
   ObjectsDeleteAll(0, PREFIX_ATAP);
   ObjectsDeleteAll(0, PREFIX_LANTAI);
   ObjectsDeleteAll(0, PREFIX_LV);
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints((ulong)MathMax(InpDeviation, 0));
   g_trade.SetAsyncMode(false);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_inRefresh = false;
   g_clccGroup = "";
   ArrayResize(g_groups, 0);
   ArrayResize(g_snaps, 0);
   ArrayResize(g_tpBatches, 0);
   ArrayResize(g_processedDeals, 0);
   ArrayResize(g_clccCl, 0);
   ArrayResize(g_clccBuy, 0);
   g_lastNewsName = "";
   InitNewsCalendar();

   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("PAC: akun bukan hedging — layer bisa tergabung.");
   if(InpNewsFilter)
      Print("PAC news filter ON. Tutup posisi + hapus pending. Jendela ",
            InpNewsMinsBefore, " mnt sebelum / ", InpNewsMinsAfter,
            " mnt sesudah rilis. Hardcode Investing high-impact USD ",
            IntegerToString(NewsCount()), " event, 1 Jan-31 Agu 2026. Filter & garis chart jam HFM.");
   if(InpHourFilter)
     {
      string hourList = "";
      for(int hw = 0; hw < ArraySize(g_hourWindows); hw++)
         hourList += (hw > 0 ? ", " : "") + g_hourWindows[hw].label;
      string modeText = "?";
      if(InpHourFilterMode == HOUR_FLATTEN_ALL)      modeText = "tutup posisi + hapus pending";
      if(InpHourFilterMode == HOUR_CANCEL_PENDING)   modeText = "hanya hapus pending, posisi terbuka jalan terus";
      if(InpHourFilterMode == HOUR_BLOCK_ENTRY_ONLY) modeText = "cuma blokir entry baru, semua yg sudah ada dibiarkan";
      Print("PAC hour filter ON (mode: ", modeText, "). Jendela jam rawan rugi (WIB): ", hourList);
     }

   g_usedTF = DetectionTF();
   ScanAndDraw();
   DrawNewsMarks();
   DrawHourMarks();
   g_lastBarTime = iTime(_Symbol, g_usedTF, 0);
   ManageOrders();
   if(!EventSetTimer(1))
      Print("PAC: EventSetTimer gagal — reentry TP window hanya saat ada tick.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   DeleteMarks();
   DeleteNewsMarks();
   DeleteHourMarks();
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   ManageFast();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   const ENUM_TIMEFRAMES tf = DetectionTF();
   if(tf != g_usedTF)
     {
      DeleteMarks();
      g_usedTF      = tf;
      g_lastBarTime = 0;
     }

   const datetime barTime = iTime(_Symbol, tf, 0);
   const bool newBar = (barTime != 0 && barTime != g_lastBarTime);
   if(newBar)
      g_lastBarTime = barTime;

   if(g_inRefresh)
      return;
   g_inRefresh = true;
   ApplyNewsFilter();
   ApplyHourFilter();
   if(newBar)
      RefreshGroupsAndClcc();
   g_inRefresh = false;

   if(newBar)
      ScanAndDraw();

   if(g_inRefresh)
      return;
   g_inRefresh = true;
   if(newBar)
      ApplyPivotCapAndSlots();
   ProcessTpBatches();
   g_inRefresh = false;
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   HandleTradeTransaction(trans);
  }

//+------------------------------------------------------------------+
void ScanAndDraw()
  {
   ScanPivots();
   ScanBases();
   ScanSrZones();
   MarkWeakness();
   MarkControls();
   ApplyClccToZones();
   DrawPivots();
   DrawBases();
   DrawSrZones();
   DrawAtapLantai();
   if(ChartVisualsOn())
      ChartRedraw(0);
  }

//+------------------------------------------------------------------+
bool IsGreen(const MqlRates &r) { return(r.close > r.open); }
bool IsRed(const MqlRates &r)   { return(r.close < r.open); }
bool IsBase(const MqlRates &r)
  {
   return(MathAbs(r.close - r.open) <= BASE_BODY_RATIO * (r.high - r.low));
  }
bool IsImpulse(const MqlRates &r)
  {
   const double range = r.high - r.low;
   if(range <= 0.0)
      return(false);
   const double ratio = MathMax(IMPULSE_BODY_PCT, 0) / 100.0;
   return(MathAbs(r.close - r.open) >= ratio * range);
  }
bool IsRally(const MqlRates &r) { return(IsGreen(r) && IsImpulse(r)); }
bool IsDrop(const MqlRates &r)  { return(IsRed(r) && IsImpulse(r)); }

//+------------------------------------------------------------------+
int PivotArrowCode(const bool isBuy)
  {
   int code = (int)InpPivotSymbol;
   if(!isBuy && (InpPivotSymbol == MARK_ARROW || InpPivotSymbol == MARK_TRIANGLE))
      code++;
   return(code);
  }

//+------------------------------------------------------------------+
bool IsGoldSymbol()
  {
   string s = _Symbol;
   StringToUpper(s);
   if(StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0)
      return(true);
   string base = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   StringToUpper(base);
   return(base == "XAU" || base == "GOLD");
  }

//+------------------------------------------------------------------+
double PipSize()
  {
   const double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   // Emas: 1 pip = 0.10 (FundedNext & HFM 2-digit: 10 point). Bukan 1 point.
   if(IsGoldSymbol())
      return((digits == 3) ? (pt * 100.0) : (pt * 10.0));
   if(digits == 3 || digits == 5)
      return(pt * 10.0);
   return(pt);
  }

//+------------------------------------------------------------------+
void AddPivot(const MqlRates &bar, const ENUM_PIVOT_TYPE type,
              const datetime c1, const datetime c2)
  {
   const int n = ArraySize(g_pivots);
   ArrayResize(g_pivots, n + 1, 64);
   g_pivots[n].time     = bar.time;
   g_pivots[n].open     = bar.open;
   g_pivots[n].high     = bar.high;
   g_pivots[n].low      = bar.low;
   g_pivots[n].close    = bar.close;
   g_pivots[n].type     = type;
   g_pivots[n].confirm1 = c1;
   g_pivots[n].confirm2 = c2;
  }

//+------------------------------------------------------------------+
void ScanPivots()
  {
   ArrayResize(g_pivots, 0);

   const int lookback = MathMax(InpLookback, 4);
   MqlRates rates[];
   const int copied = CopyRates(_Symbol, DetectionTF(), 0, lookback, rates);
   if(copied < 4)
      return;
   ArraySetAsSeries(rates, false);

   const int lastClosed = copied - 2;

   int      buyCand   = -1;
   int      buyGreens = 0;
   datetime buyConf1  = 0;

   int      sellCand = -1;
   int      sellReds = 0;
   datetime sellConf1 = 0;

   for(int i = 1; i <= lastClosed; i++)
     {
      //--- Pivot Buy: rolling candidate, 2 candle hijau konfirmasi
      if(buyCand >= 0)
        {
         if(rates[i].low < rates[buyCand].low)
           {
            buyCand   = i;
            buyGreens = 0;
            buyConf1  = 0;
           }
         else if(IsGreen(rates[i]) && rates[i].open > rates[buyCand].close)
           {
            buyGreens++;
            if(buyGreens == 1)
               buyConf1 = rates[i].time;
            else
              {
               AddPivot(rates[buyCand], PIVOT_BUY, buyConf1, rates[i].time);
               buyCand   = -1;
               buyGreens = 0;
               buyConf1  = 0;
              }
           }
        }
      if(buyCand < 0 && rates[i].low < rates[i - 1].low)
        {
         buyCand   = i;
         buyGreens = 0;
         buyConf1  = 0;
        }

      //--- Pivot Sell: cermin dari Buy
      if(sellCand >= 0)
        {
         if(rates[i].high > rates[sellCand].high)
           {
            sellCand  = i;
            sellReds  = 0;
            sellConf1 = 0;
           }
         else if(IsRed(rates[i]) && rates[i].open < rates[sellCand].close)
           {
            sellReds++;
            if(sellReds == 1)
               sellConf1 = rates[i].time;
            else
              {
               AddPivot(rates[sellCand], PIVOT_SELL, sellConf1, rates[i].time);
               sellCand  = -1;
               sellReds  = 0;
               sellConf1 = 0;
              }
           }
        }
      if(sellCand < 0 && rates[i].high > rates[i - 1].high)
        {
         sellCand  = i;
         sellReds  = 0;
         sellConf1 = 0;
        }
     }
  }

//+------------------------------------------------------------------+
void AddBase(const MqlRates &bar)
  {
   const int n = ArraySize(g_bases);
   ArrayResize(g_bases, n + 1, 64);
   g_bases[n].time  = bar.time;
   g_bases[n].open  = bar.open;
   g_bases[n].high  = bar.high;
   g_bases[n].low   = bar.low;
   g_bases[n].close = bar.close;
  }

//+------------------------------------------------------------------+
void ScanBases()
  {
   ArrayResize(g_bases, 0);

   const int lookback = MathMax(InpLookback, 4);
   MqlRates rates[];
   const int copied = CopyRates(_Symbol, DetectionTF(), 0, lookback, rates);
   if(copied < 4)
      return;
   ArraySetAsSeries(rates, false);

   const int lastClosed = copied - 2;
   for(int i = 0; i <= lastClosed; i++)
     {
      if(IsBase(rates[i]))
         AddBase(rates[i]);
     }
  }

//+------------------------------------------------------------------+
void CoverAdd(double &cLo[], double &cHi[], int &n, double a, double b)
  {
   const double eps = _Point;
   int i = 0;
   while(i < n)
     {
      if(b + eps < cLo[i] || a - eps > cHi[i])
        {
         i++;
         continue;
        }
      a = MathMin(a, cLo[i]);
      b = MathMax(b, cHi[i]);
      for(int k = i; k < n - 1; k++)
        {
         cLo[k] = cLo[k + 1];
         cHi[k] = cHi[k + 1];
        }
      n--;
      i = 0;
     }
   ArrayResize(cLo, n + 1);
   ArrayResize(cHi, n + 1);
   cLo[n] = a;
   cHi[n] = b;
   n++;
  }

//+------------------------------------------------------------------+
void CoverClipAdd(double &cLo[], double &cHi[], int &n,
                  const double a, const double b,
                  const double zoneLow, const double zoneHigh)
  {
   const double lo = MathMax(MathMin(a, b), zoneLow);
   const double hi = MathMin(MathMax(a, b), zoneHigh);
   if(hi > lo)
      CoverAdd(cLo, cHi, n, lo, hi);
  }

//+------------------------------------------------------------------+
bool CoverFull(const double &cLo[], const double &cHi[], const int n,
               const double zoneLow, const double zoneHigh)
  {
   if(n <= 0)
      return(false);

   const double eps = _Point;
   int order[];
   ArrayResize(order, n);
   for(int i = 0; i < n; i++)
      order[i] = i;
   for(int i = 0; i < n - 1; i++)
      for(int k = i + 1; k < n; k++)
         if(cLo[order[k]] < cLo[order[i]])
           {
            const int tmp = order[i];
            order[i] = order[k];
            order[k] = tmp;
           }

   double curLo = cLo[order[0]];
   double curHi = cHi[order[0]];
   for(int i = 1; i < n; i++)
     {
      const int k = order[i];
      if(cLo[k] <= curHi + eps)
         curHi = MathMax(curHi, cHi[k]);
      else
        {
         if(curLo <= zoneLow + eps && curHi >= zoneHigh - eps)
            return(true);
         curLo = cLo[k];
         curHi = cHi[k];
        }
     }
   return(curLo <= zoneLow + eps && curHi >= zoneHigh - eps);
  }

//+------------------------------------------------------------------+
datetime ZoneRightTime(const MqlRates &rates[], const int copied, const int lastBaseIdx,
                       const double zoneHigh, const double zoneLow, const bool isSupport)
  {
   const int start = lastBaseIdx + 2; // skip Base + leg (C3)
   if(start >= copied)
      return(rates[copied - 1].time);

   double cLo[], cHi[];
   int n = 0;
   bool painting = false;
   double prevClose = 0.0;

   for(int j = start; j < copied; j++)
     {
      if(!painting)
        {
         const bool returned = isSupport
                               ? (rates[j].close < zoneHigh)
                               : (rates[j].close > zoneLow);
         if(!returned)
            continue;
         painting = true;
        }
      else
         CoverClipAdd(cLo, cHi, n, prevClose, rates[j].open, zoneLow, zoneHigh);

      CoverClipAdd(cLo, cHi, n,
                   MathMin(rates[j].open, rates[j].close),
                   MathMax(rates[j].open, rates[j].close),
                   zoneLow, zoneHigh);
      prevClose = rates[j].close;

      if(CoverFull(cLo, cHi, n, zoneLow, zoneHigh))
         return(rates[j].time);
     }
   return(rates[copied - 1].time);
  }

//+------------------------------------------------------------------+
void AddSrZone(const datetime left, const datetime right, const datetime lastBase,
               const double hi, const double lo, const bool isSupport)
  {
   const int n = ArraySize(g_zones);
   ArrayResize(g_zones, n + 1, 32);
   g_zones[n].left      = left;
   g_zones[n].right     = right;
   g_zones[n].lastBase  = lastBase;
   g_zones[n].high      = hi;
   g_zones[n].low       = lo;
   g_zones[n].isSupport = isSupport;
   g_zones[n].isControl    = false;
   g_zones[n].isWeak       = false;
   g_zones[n].pivotTime    = 0;
   g_zones[n].pivotTouches = 0;
  }

//+------------------------------------------------------------------+
void ScanSrZones()
  {
   ArrayResize(g_zones, 0);

   const int n = ArraySize(g_bases);
   if(n <= 0)
      return;

   const int lookback = MathMax(InpLookback, 4);
   MqlRates rates[];
   const int copied = CopyRates(_Symbol, DetectionTF(), 0, lookback, rates);
   if(copied < 4)
      return;
   ArraySetAsSeries(rates, false);

   int idx[];
   ArrayResize(idx, n);
   int ri = 0;
   for(int b = 0; b < n; b++)
     {
      while(ri < copied && rates[ri].time < g_bases[b].time)
         ri++;
      idx[b] = (ri < copied && rates[ri].time == g_bases[b].time) ? ri : -1;
     }

   int s = 0;
   while(s < n)
     {
      if(idx[s] < 0)
        {
         s++;
         continue;
        }
      int e = s;
      double hi = g_bases[s].high;
      double lo = g_bases[s].low;
      while(e + 1 < n && idx[e] >= 0 && idx[e + 1] == idx[e] + 1)
        {
         e++;
         if(g_bases[e].high > hi)
            hi = g_bases[e].high;
         if(g_bases[e].low < lo)
            lo = g_bases[e].low;
        }

      const int count = e - s + 1;
      const int leftIdx = idx[s];
      const int rightIdx = idx[e];
      const int lastClosed = copied - 2;
      const int maxGroup = MathMax(InpMaxBaseCandles, 1);
      const bool sizedOk = (count >= 1 && count <= maxGroup);
      const bool legsOk  = (leftIdx >= 1 && rightIdx + 1 <= lastClosed);

      if(sizedOk && legsOk)
        {
         const MqlRates c1 = rates[leftIdx - 1];
         const MqlRates c3 = rates[rightIdx + 1];
         if(IsRally(c1) && IsRally(c3) && c3.close > hi)
            AddSrZone(g_bases[s].time,
                      ZoneRightTime(rates, copied, rightIdx, hi, lo, true),
                      g_bases[e].time, hi, lo, true);
         else if(IsDrop(c1) && IsDrop(c3) && c3.close < lo)
            AddSrZone(g_bases[s].time,
                      ZoneRightTime(rates, copied, rightIdx, hi, lo, false),
                      g_bases[e].time, hi, lo, false);
        }
      s = e + 1;
     }
  }

//+------------------------------------------------------------------+
void MarkWeakness()
  {
   const int nz = ArraySize(g_zones);
   if(nz <= 0)
      return;

   const int lookback = MathMax(InpLookback, 4);
   MqlRates rates[];
   const int copied = CopyRates(_Symbol, DetectionTF(), 0, lookback, rates);
   if(copied < 4)
      return;
   ArraySetAsSeries(rates, false);

   const int lastClosed = copied - 2;

   for(int z = 0; z < nz; z++)
     {
      g_zones[z].isWeak = false;
      int lastIdx = -1;
      for(int i = 0; i < copied; i++)
        {
         if(rates[i].time == g_zones[z].lastBase)
           {
            lastIdx = i;
            break;
           }
        }
      if(lastIdx < 0)
         continue;

      for(int j = lastIdx + 2; j <= lastClosed; j++)
        {
         const double bodyLo = MathMin(rates[j].open, rates[j].close);
         const double bodyHi = MathMax(rates[j].open, rates[j].close);
         if(g_zones[z].isSupport)
           {
            if(bodyLo <= g_zones[z].low)
              {
               g_zones[z].isWeak = true;
               break;
              }
           }
         else if(bodyHi >= g_zones[z].high)
           {
            g_zones[z].isWeak = true;
            break;
           }
        }
     }
  }

//+------------------------------------------------------------------+
bool RangesOverlap(const double aHi, const double aLo, const double bHi, const double bLo)
  {
   return(aLo <= bHi && aHi >= bLo);
  }

//+------------------------------------------------------------------+
void MarkControls()
  {
   const int nz = ArraySize(g_zones);
   const int np = ArraySize(g_pivots);
   for(int z = 0; z < nz; z++)
     {
      g_zones[z].isControl    = false;
      g_zones[z].pivotTime    = 0;
      g_zones[z].pivotTouches = 0;
      const ENUM_PIVOT_TYPE need = g_zones[z].isSupport ? PIVOT_BUY : PIVOT_SELL;
      datetime lastPt = 0;
      int touches = 0;
      for(int p = 0; p < np; p++)
        {
         if(g_pivots[p].type != need)
            continue;
         if(g_pivots[p].time <= g_zones[z].lastBase)
            continue;
         if(!RangesOverlap(g_pivots[p].high, g_pivots[p].low,
                           g_zones[z].high, g_zones[z].low))
            continue;
         touches++;
         lastPt = g_pivots[p].time;
        }
      if(touches <= 0)
         continue;
      g_zones[z].isControl    = true;
      g_zones[z].pivotTime    = lastPt;
      g_zones[z].pivotTouches = touches;
     }
  }

//+------------------------------------------------------------------+
void DrawPivots()
  {
   if(!ChartVisualsOn())
      return;
   ObjectsDeleteAll(0, PREFIX_PB);
   ObjectsDeleteAll(0, PREFIX_PS);

   const double gap = MathMax(InpGapPips, 0) * PipSize();
   const int n = ArraySize(g_pivots);
   for(int i = 0; i < n; i++)
      CreateArrow(g_pivots[i], gap);
  }

//+------------------------------------------------------------------+
void CreateArrow(const Pivot &p, const double gap)
  {
   const bool isBuy = (p.type == PIVOT_BUY);
   const string name = (isBuy ? PREFIX_PB : PREFIX_PS) + IntegerToString((long)p.time);
   const double price = isBuy ? (p.low - gap) : (p.high + gap);

   if(!ObjectCreate(0, name, OBJ_ARROW, 0, p.time, price))
      return;

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, PivotArrowCode(isBuy));
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, isBuy ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpPivotColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
                   StringFormat("%s ke-%d\n%s\nO=%s H=%s L=%s C=%s\nConf: %s | %s",
                                isBuy ? "PAC Pivot Buy" : "PAC Pivot Sell",
                                PivotRank(p.time, p.type),
                                TimeToString(p.time, TIME_DATE | TIME_MINUTES),
                                DoubleToString(p.open, _Digits),
                                DoubleToString(p.high, _Digits),
                                DoubleToString(p.low, _Digits),
                                DoubleToString(p.close, _Digits),
                                TimeToString(p.confirm1, TIME_DATE | TIME_MINUTES),
                                TimeToString(p.confirm2, TIME_DATE | TIME_MINUTES)));
  }

//+------------------------------------------------------------------+
void DrawBases()
  {
   if(!ChartVisualsOn())
      return;
   ObjectsDeleteAll(0, PREFIX_BASE);
   ObjectsDeleteAll(0, PREFIX_RBR);
   ObjectsDeleteAll(0, PREFIX_DBD);

   const int n = ArraySize(g_bases);
   for(int i = 0; i < n; i++)
      CreateBaseLine(g_bases[i]);
  }

//+------------------------------------------------------------------+
void CreateBaseLine(const Base &b)
  {
   const string name = PREFIX_BASE + IntegerToString((long)b.time);

   if(!ObjectCreate(0, name, OBJ_TREND, 0, b.time, b.high, b.time, b.low))
      return;

   ObjectSetInteger(0, name, OBJPROP_COLOR, InpBaseColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
                   StringFormat("PAC Candle Base\n%s\nO=%s H=%s L=%s C=%s",
                                TimeToString(b.time, TIME_DATE | TIME_MINUTES),
                                DoubleToString(b.open, _Digits),
                                DoubleToString(b.high, _Digits),
                                DoubleToString(b.low, _Digits),
                                DoubleToString(b.close, _Digits)));
  }

//+------------------------------------------------------------------+
void DrawSrZones()
  {
   if(!ChartVisualsOn())
      return;
   ObjectsDeleteAll(0, PREFIX_SUP);
   ObjectsDeleteAll(0, PREFIX_RES);

   const int n = ArraySize(g_zones);
   for(int i = 0; i < n; i++)
      CreateSrRect(g_zones[i]);
  }

//+------------------------------------------------------------------+
void CreateSrRect(const SrZone &z)
  {
   const string name = (z.isSupport ? PREFIX_SUP : PREFIX_RES) + IntegerToString((long)z.left);
   const bool aktif  = (z.isControl && !z.isWeak);
   const bool off    = (z.isControl && z.isWeak);
   const string side = z.isSupport ? "Lantai" : "Atap";

   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, z.left, z.high, z.right, z.low))
      return;

   ObjectSetInteger(0, name, OBJPROP_COLOR, z.isSupport ? InpSupportColor : InpResistColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE, aktif ? STYLE_SOLID : (off ? STYLE_DOT : STYLE_DASH));
   ObjectSetInteger(0, name, OBJPROP_WIDTH, aktif ? 2 : 1);
   ObjectSetInteger(0, name, OBJPROP_FILL, aktif);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);

   string tip = "PAC Control Standby " + side;
   if(aktif)
      tip = "PAC Control Aktif " + side;
   else if(off)
      tip = "PAC Control Off " + side;
   if(z.isControl && z.pivotTime > 0)
     {
      const int rk = PivotRank(z.pivotTime, z.isSupport ? PIVOT_BUY : PIVOT_SELL);
      tip += "\nPivot ke-" + IntegerToString(rk) + "  " +
             TimeToString(z.pivotTime, TIME_DATE | TIME_MINUTES);
      tip += "\nSentuhan pivot " + IntegerToString(z.pivotTouches) + "/" +
             IntegerToString(MaxPivotTouches());
     }
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
                   StringFormat("%s\n%s -> %s\nH=%s L=%s",
                                tip,
                                TimeToString(z.left, TIME_DATE | TIME_MINUTES),
                                TimeToString(z.right, TIME_DATE | TIME_MINUTES),
                                DoubleToString(z.high, _Digits),
                                DoubleToString(z.low, _Digits)));
  }

//+------------------------------------------------------------------+
void CreateLevelLine(const string name, const double price, const color clr, const string tip,
                     const ENUM_LINE_STYLE style = STYLE_SOLID, const int width = 2)
  {
   if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
  }

//+------------------------------------------------------------------+
int PivotRank(const datetime t, const ENUM_PIVOT_TYPE type)
  {
   if(t <= 0)
      return(0);
   int rank = 0;
   const int np = ArraySize(g_pivots);
   for(int i = 0; i < np; i++)
     {
      if(g_pivots[i].type != type)
         continue;
      if(g_pivots[i].time <= t)
         rank++;
     }
   return(rank);
  }

//+------------------------------------------------------------------+
bool WasClcc(const bool isBuy, const double cl)
  {
   const int n = ArraySize(g_clccCl);
   for(int i = 0; i < n; i++)
     {
      if(g_clccBuy[i] == isBuy && SameCl(g_clccCl[i], cl))
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
void RememberClcc(const PacGroup &g)
  {
   const bool isBuy = (g.direction > 0);
   if(WasClcc(isBuy, g.clPrice))
      return;
   const int n = ArraySize(g_clccCl);
   ArrayResize(g_clccCl, n + 1);
   ArrayResize(g_clccBuy, n + 1);
   g_clccCl[n]  = g.clPrice;
   g_clccBuy[n] = isBuy;
  }

//+------------------------------------------------------------------+
void ApplyClccToZones()
  {
   const double pip = PipSize();
   const int n = ArraySize(g_zones);
   for(int i = 0; i < n; i++)
     {
      const bool isBuy = g_zones[i].isSupport;
      const double cl = isBuy
                        ? NormalizePrice(g_zones[i].low - MathMax(InpCLBuffer, 0) * pip)
                        : NormalizePrice(g_zones[i].high + MathMax(InpCLBuffer, 0) * pip);
      if(WasClcc(isBuy, cl))
         g_zones[i].isWeak = true;
     }
  }

//+------------------------------------------------------------------+
bool ZoneOrderEligible(const SrZone &z)
  {
   if(!z.isControl || z.isWeak)
      return(false);
   if(z.pivotTouches >= MaxPivotTouches())
      return(false);
   const bool isBuy = z.isSupport;
   const double cl = isBuy
                     ? NormalizePrice(z.low - MathMax(InpCLBuffer, 0) * PipSize())
                     : NormalizePrice(z.high + MathMax(InpCLBuffer, 0) * PipSize());
   return(!WasClcc(isBuy, cl));
  }

//+------------------------------------------------------------------+
int MaxGroupsPerSide()
  {
   int n = InpMaxGroupsPerSide;
   if(n < 1)
      n = 1;
   return(n);
  }

//+------------------------------------------------------------------+
int MaxPivotTouches()
  {
   int n = InpMaxPivotTouches;
   if(n < 1)
      n = 1;
   return(n);
  }

//+------------------------------------------------------------------+
void ZoneClTp(const SrZone &z, const double maxW, double &cl, double &tp)
  {
   const double pip = PipSize();
   const double buf = MathMax(InpCLBuffer, 0) * pip;
   if(z.isSupport)
     {
      cl = NormalizePrice(z.low - buf);
      tp = NormalizePrice(z.low + maxW * 0.5);
     }
   else
     {
      cl = NormalizePrice(z.high + buf);
      tp = NormalizePrice(z.high - maxW * 0.5);
     }
  }

//+------------------------------------------------------------------+
bool TpClOverlap(const double clA, const double tpA,
                 const double clB, const double tpB)
  {
   if(clA <= 0.0 || tpA <= 0.0 || clB <= 0.0 || tpB <= 0.0)
      return(false);
   const double loA = MathMin(clA, tpA);
   const double hiA = MathMax(clA, tpA);
   const double loB = MathMin(clB, tpB);
   const double hiB = MathMax(clB, tpB);
   const double eps = MathMax(_Point * 5.0, PipSize() * 0.05);
   return(loA < hiB - eps && hiA > loB + eps);
  }

//+------------------------------------------------------------------+
void CollectPacSideRanges(const bool wantBuy, double &cl[], double &tp[], int &nOut,
                          const LiveItem &items[])
  {
   nOut = 0;
   ArrayResize(cl, 0);
   ArrayResize(tp, 0);
   for(int i = 0; i < ArraySize(items); i++)
     {
      if(!items[i].parsed)
         continue;
      if(items[i].pac.isBuy != wantBuy)
         continue;
      const double c = items[i].pac.clPrice;
      const double t = items[i].tp;
      if(c <= 0.0)
         continue;
      bool dup = false;
      for(int k = 0; k < nOut; k++)
        {
         if(!SameCl(cl[k], c))
            continue;
         if(t > 0.0 && (tp[k] <= 0.0 || MathAbs(t - c) > MathAbs(tp[k] - c)))
            tp[k] = t;
         dup = true;
         break;
        }
      if(dup)
         continue;
      nOut++;
      ArrayResize(cl, nOut);
      ArrayResize(tp, nOut);
      cl[nOut - 1] = c;
      tp[nOut - 1] = t;
     }
  }

//+------------------------------------------------------------------+
bool IdxHas(const int &idx[], const int n, const int v)
  {
   for(int i = 0; i < n; i++)
     {
      if(idx[i] == v)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
void CollectNearestZones(const bool wantBuy, const double bid, const double maxW,
                         int &idx[], int &nOut, double &keepCl[], int &nKeep,
                         const LiveItem &items[])
  {
   nOut  = 0;
   nKeep = 0;
   ArrayResize(idx, 0);
   ArrayResize(keepCl, 0);
   int    zIdx[];
   double dist[];
   double zCl[];
   double zTp[];
   int    nCand = 0;
   const int nz = ArraySize(g_zones);
   const ENUM_TIMEFRAMES tf = DetectionTF();

   for(int z = 0; z < nz; z++)
     {
      if(!ZoneOrderEligible(g_zones[z]))
         continue;
      double d = 0.0;
      double cl = 0.0;
      double tp = 0.0;
      ZoneClTp(g_zones[z], maxW, cl, tp);
      if(wantBuy)
        {
         if(!g_zones[z].isSupport || g_zones[z].low > bid)
            continue;
         d = bid - g_zones[z].low;
        }
      else
        {
         if(g_zones[z].isSupport || g_zones[z].high < bid)
            continue;
         d = g_zones[z].high - bid;
        }
      if(ClBrokenOnClosedBar(wantBuy, cl, tf))
         continue;
      nCand++;
      ArrayResize(zIdx, nCand);
      ArrayResize(dist, nCand);
      ArrayResize(zCl, nCand);
      ArrayResize(zTp, nCand);
      zIdx[nCand - 1] = z;
      dist[nCand - 1] = d;
      zCl[nCand - 1]  = cl;
      zTp[nCand - 1]  = tp;
     }

   double oldCl[];
   double oldTp[];
   int    nOld = 0;
   CollectPacSideRanges(wantBuy, oldCl, oldTp, nOld, items);

   bool skip[];
   ArrayResize(skip, nCand);
   const double epsW = MathMax(_Point * 5.0, PipSize() * 0.05);
   for(int i = 0; i < nCand; i++)
     {
      skip[i] = false;
      for(int j = 0; j < nCand; j++)
        {
         if(i == j)
            continue;
         if(!TpClOverlap(zCl[i], zTp[i], zCl[j], zTp[j]))
            continue;
         const double wI = MathAbs(zCl[i] - zTp[i]);
         const double wJ = MathAbs(zCl[j] - zTp[j]);
         if(wI < wJ - epsW)
           {
            skip[i] = true;
            break;
           }
         if(MathAbs(wI - wJ) <= epsW && dist[i] < dist[j])
           {
            skip[i] = true;
            break;
           }
        }
      if(skip[i])
         continue;
      for(int o = 0; o < nOld; o++)
        {
         if(TpClOverlap(zCl[i], zTp[i], oldCl[o], oldTp[o]))
           {
            skip[i] = true;
            break;
           }
        }
     }

   int    fIdx[];
   double fDist[];
   double fCl[];
   int    nF = 0;
   for(int i = 0; i < nCand; i++)
     {
      if(skip[i])
         continue;
      nF++;
      ArrayResize(fIdx, nF);
      ArrayResize(fDist, nF);
      ArrayResize(fCl, nF);
      fIdx[nF - 1]  = zIdx[i];
      fDist[nF - 1] = dist[i];
      fCl[nF - 1]   = zCl[i];
     }

   for(int i = 1; i < nF; i++)
     {
      for(int j = i; j > 0; j--)
        {
         if(fDist[j] >= fDist[j - 1])
            break;
         const int    ti = fIdx[j];
         const double td = fDist[j];
         const double tc = fCl[j];
         fIdx[j]      = fIdx[j - 1];
         fDist[j]     = fDist[j - 1];
         fCl[j]       = fCl[j - 1];
         fIdx[j - 1]  = ti;
         fDist[j - 1] = td;
         fCl[j - 1]   = tc;
        }
     }

   double pCl[];
   double pDist[];
   int    nProt = 0;
   for(int o = 0; o < nOld; o++)
     {
      bool already = false;
      for(int i = 0; i < nF; i++)
        {
         if(SameCl(fCl[i], oldCl[o]))
           {
            already = true;
            break;
           }
        }
      if(already)
         continue;
      bool protects = false;
      for(int i = 0; i < nCand; i++)
        {
         if(!skip[i])
            continue;
         if(TpClOverlap(zCl[i], zTp[i], oldCl[o], oldTp[o]))
           {
            protects = true;
            break;
           }
        }
      if(!protects)
         continue;
      double d = 0.0;
      if(wantBuy)
         d = bid - oldCl[o];
      else
         d = oldCl[o] - bid;
      if(d < 0.0)
         d = 0.0;
      nProt++;
      ArrayResize(pCl, nProt);
      ArrayResize(pDist, nProt);
      pCl[nProt - 1]   = oldCl[o];
      pDist[nProt - 1] = d;
     }

   const int cap = MaxGroupsPerSide();
   const int nMerge = nF + nProt;
   bool takeNew[];
   int  takePi[];
   double takeDist[];
   ArrayResize(takeNew, nMerge);
   ArrayResize(takePi, nMerge);
   ArrayResize(takeDist, nMerge);
   for(int i = 0; i < nF; i++)
     {
      takeNew[i]  = true;
      takePi[i]   = i;
      takeDist[i] = fDist[i];
     }
   for(int i = 0; i < nProt; i++)
     {
      const int k = nF + i;
      takeNew[k]  = false;
      takePi[k]   = i;
      takeDist[k] = pDist[i];
     }
   for(int i = 1; i < nMerge; i++)
     {
      for(int j = i; j > 0; j--)
        {
         if(takeDist[j] >= takeDist[j - 1])
            break;
         const bool   tn = takeNew[j];
         const int    tp = takePi[j];
         const double td = takeDist[j];
         takeNew[j]      = takeNew[j - 1];
         takePi[j]       = takePi[j - 1];
         takeDist[j]     = takeDist[j - 1];
         takeNew[j - 1]  = tn;
         takePi[j - 1]   = tp;
         takeDist[j - 1] = td;
        }
     }

   nOut  = 0;
   nKeep = 0;
   ArrayResize(idx, 0);
   ArrayResize(keepCl, 0);
   const int takeN = (nMerge > cap ? cap : nMerge);
   for(int i = 0; i < takeN; i++)
     {
      if(takeNew[i])
        {
         nOut++;
         ArrayResize(idx, nOut);
         idx[nOut - 1] = fIdx[takePi[i]];
        }
      else
        {
         nKeep++;
         ArrayResize(keepCl, nKeep);
         keepCl[nKeep - 1] = pCl[takePi[i]];
        }
     }
  }

//+------------------------------------------------------------------+
int LayerCount()
  {
   int n = InpLayerCount;
   if(n < 1)
      n = 1;
   if(n > 9)
      n = 9;
   return(n);
  }

//+------------------------------------------------------------------+
double LayerLot(const int pos)
  {
   double lot = InpLot;
   if(InpLotStepUp && LayerCount() > 1 && pos > 0)
      lot = InpLot * (double)pos;
   return(NormalizeLot(lot));
  }

//+------------------------------------------------------------------+
void CalcEntryClSl(const bool isBuy, const double extreme, const double tp,
                   double &entry1, double &cl, double &sl)
  {
   const double pip = PipSize();
   const double clBuf = MathMax(InpCLBuffer, 0) * pip;
   const double ratio = MathMax(InpSLRatio, 0) / 100.0;
   if(isBuy)
     {
      entry1 = extreme + 0.5 * (tp - extreme);
      cl     = extreme - clBuf;
      sl     = cl - ratio * MathAbs(tp - cl);
     }
   else
     {
      entry1 = extreme - 0.5 * (extreme - tp);
      cl     = extreme + clBuf;
      sl     = cl + ratio * MathAbs(cl - tp);
     }
   cl = NormalizePrice(cl);
   sl = NormalizePrice(sl);
  }

//+------------------------------------------------------------------+
void DrawSellLevels(const double atap, const double tp, const string kind, const bool drawTp)
  {
   double entry1 = 0.0;
   double cl     = 0.0;
   double sl     = 0.0;
   CalcEntryClSl(false, atap, tp, entry1, cl, sl);
   const int n = LayerCount();

   if(drawTp)
      CreateLevelLine(PREFIX_LV + "TP_S", tp, clrGold,
                      StringFormat("PAC TP Sell (%s)\n%s", kind, DoubleToString(tp, _Digits)));
   CreateLevelLine(PREFIX_LV + "CL_S", cl, clrOrange,
                   StringFormat("PAC CL Sell\n%s", DoubleToString(cl, _Digits)), STYLE_DASH);
   CreateLevelLine(PREFIX_LV + "SL_S", sl, clrSilver,
                   StringFormat("PAC SL Sell\n%s", DoubleToString(sl, _Digits)), STYLE_DOT);

   for(int i = 1; i <= n; i++)
     {
      const double entry = entry1 + (atap - entry1) * (double)(i - 1) / (double)n;
      CreateLevelLine(PREFIX_LV + "ES" + IntegerToString(i), entry, InpResistColor,
                      StringFormat("PAC Entry Sell %d/%d\n%s", i, n, DoubleToString(entry, _Digits)),
                      STYLE_DASH, 1);
     }
  }

//+------------------------------------------------------------------+
void DrawBuyLevels(const double lantai, const double tp, const string kind, const bool drawTp)
  {
   double entry1 = 0.0;
   double cl     = 0.0;
   double sl     = 0.0;
   CalcEntryClSl(true, lantai, tp, entry1, cl, sl);
   const int n = LayerCount();

   if(drawTp)
      CreateLevelLine(PREFIX_LV + "TP_B", tp, clrGold,
                      StringFormat("PAC TP Buy (%s)\n%s", kind, DoubleToString(tp, _Digits)));
   CreateLevelLine(PREFIX_LV + "CL_B", cl, clrOrange,
                   StringFormat("PAC CL Buy\n%s", DoubleToString(cl, _Digits)), STYLE_DASH);
   CreateLevelLine(PREFIX_LV + "SL_B", sl, clrSilver,
                   StringFormat("PAC SL Buy\n%s", DoubleToString(sl, _Digits)), STYLE_DOT);

   for(int i = 1; i <= n; i++)
     {
      const double entry = entry1 + (lantai - entry1) * (double)(i - 1) / (double)n;
      CreateLevelLine(PREFIX_LV + "EB" + IntegerToString(i), entry, InpSupportColor,
                      StringFormat("PAC Entry Buy %d/%d\n%s", i, n, DoubleToString(entry, _Digits)),
                      STYLE_DASH, 1);
     }
  }

//+------------------------------------------------------------------+
void DrawAtapLantai()
  {
   const bool draw = ChartVisualsOn();
   if(draw)
     {
      ObjectsDeleteAll(0, PREFIX_ATAP);
      ObjectsDeleteAll(0, PREFIX_LANTAI);
      ObjectsDeleteAll(0, PREFIX_LV);
     }

   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0)
      return;

   int atapIdx = -1;
   int lantaiIdx = -1;
   double bestAtap = DBL_MAX;
   double bestLantai = DBL_MAX;

   const int n = ArraySize(g_zones);
   for(int i = 0; i < n; i++)
     {
      if(!ZoneOrderEligible(g_zones[i]))
         continue;
      if(g_zones[i].isSupport)
        {
         if(g_zones[i].low > bid)
            continue;
         const double dist = bid - g_zones[i].low;
         if(dist < bestLantai)
           {
            bestLantai = dist;
            lantaiIdx = i;
           }
        }
      else
        {
         if(g_zones[i].high < bid)
            continue;
         const double dist = g_zones[i].high - bid;
         if(dist < bestAtap)
           {
            bestAtap = dist;
            atapIdx = i;
           }
        }
     }

   const bool hasAtap   = (atapIdx >= 0);
   const bool hasLantai = (lantaiIdx >= 0);
   const double atap   = hasAtap   ? g_zones[atapIdx].high : 0.0;
   const double lantai = hasLantai ? g_zones[lantaiIdx].low : 0.0;
   const double maxW   = MathMax(InpMaxAreaWidth, 1) * PipSize();
   const bool paired   = (hasAtap && hasLantai && (atap - lantai) <= maxW && atap > lantai);

   if(draw)
     {
      if(hasAtap)
        {
         const SrZone z = g_zones[atapIdx];
         const int rk = PivotRank(z.pivotTime, PIVOT_SELL);
         CreateLevelLine(PREFIX_ATAP, z.high, InpResistColor,
                         StringFormat("PAC Atap (Pivot Sell ke-%d)\n%s\nH=%s",
                                      rk,
                                      TimeToString(z.left, TIME_DATE | TIME_MINUTES),
                                      DoubleToString(z.high, _Digits)));
        }
      if(hasLantai)
        {
         const SrZone z = g_zones[lantaiIdx];
         const int rk = PivotRank(z.pivotTime, PIVOT_BUY);
         CreateLevelLine(PREFIX_LANTAI, z.low, InpSupportColor,
                         StringFormat("PAC Lantai (Pivot Buy ke-%d)\n%s\nL=%s",
                                      rk,
                                      TimeToString(z.left, TIME_DATE | TIME_MINUTES),
                                      DoubleToString(z.low, _Digits)));
        }

      if(paired)
        {
         const double tp = (atap + lantai) * 0.5;
         CreateLevelLine(PREFIX_LV + "TP", tp, clrGold,
                         StringFormat("PAC TP (Paired)\n%s", DoubleToString(tp, _Digits)));
         DrawSellLevels(atap, tp, "Paired", false);
         DrawBuyLevels(lantai, tp, "Paired", false);
        }
      else
        {
         const double tpS = hasAtap   ? (atap - maxW * 0.5)   : 0.0;
         const double tpB = hasLantai ? (lantai + maxW * 0.5) : 0.0;
         if(hasAtap)
            DrawSellLevels(atap, tpS, "Mandiri", true);
         if(hasLantai)
            DrawBuyLevels(lantai, tpB, "Mandiri", true);
        }
     }
   MaybeSendEligible(atapIdx, lantaiIdx, paired, maxW);
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
string TfTag()
  {
   string s = EnumToString(DetectionTF());
   const int p = StringFind(s, "_");
   if(p >= 0)
      return(StringSubstr(s, p + 1));
   return(s);
  }

//+------------------------------------------------------------------+
string StampNow(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return(StringFormat("%02d%02d%02d.%02d%02d%02d",
                       dt.year % 100, dt.mon, dt.day,
                       dt.hour, dt.min, dt.sec));
  }

//+------------------------------------------------------------------+
string MakeComment(const bool paired, const bool isBuy, const int layers, const int pos,
                   const double cl, const string ts)
  {
   const string head = StringFormat("%s%s%d%d/%s/",
                                    paired ? "P" : "M",
                                    isBuy ? "B" : "S",
                                    layers, pos,
                                    TfTag());
   const string tail = "/" + ts;
   int budget = 30 - StringLen(head) - StringLen(tail);
   if(budget < 1)
      budget = 1;
   int d = _Digits;
   string clt = DoubleToString(NormalizePrice(cl), d);
   while(StringLen(clt) > budget && d > 0)
     {
      d--;
      clt = DoubleToString(NormalizePrice(cl), d);
     }
   if(StringLen(clt) > budget)
      clt = StringSubstr(clt, 0, budget);
   return(head + clt + tail);
  }

//+------------------------------------------------------------------+
bool ParsePacCommentEx(const string cmt, PacCmt &out)
  {
   out.groupCode  = "";
   out.isBuy      = false;
   out.paired     = false;
   out.layerCount = 0;
   out.position   = 0;
   out.timeframe  = PERIOD_CURRENT;
   out.clPrice    = 0.0;
   out.tfText     = "";
   out.stamp      = "";

   string parts[];
   const int n = StringSplit(cmt, '/', parts);
   if(n < 4)
      return(false);
   if(StringLen(parts[0]) != 4)
      return(false);
   const ushort c0 = StringGetCharacter(parts[0], 0);
   const ushort c1 = StringGetCharacter(parts[0], 1);
   if((c0 != 'P' && c0 != 'M') || (c1 != 'B' && c1 != 'S'))
      return(false);
   const int d2 = (int)(StringGetCharacter(parts[0], 2) - '0');
   const int d3 = (int)(StringGetCharacter(parts[0], 3) - '0');
   if(d2 < 1 || d2 > 9 || d3 < 1 || d3 > 9 || d3 > d2)
      return(false);
   ENUM_TIMEFRAMES tf = PERIOD_CURRENT;
   if(!TimeframeFromString(parts[1], tf))
      return(false);
   const double cl = StringToDouble(parts[2]);
   if(cl <= 0.0 || StringLen(parts[3]) < 8)
      return(false);

   out.paired     = (c0 == 'P');
   out.isBuy      = (c1 == 'B');
   out.layerCount = d2;
   out.position   = d3;
   out.timeframe  = tf;
   out.clPrice    = cl;
   out.tfText     = parts[1];
   out.stamp      = parts[3];
   out.groupCode  = StringSubstr(parts[0], 0, 2) + "-" + parts[3];
   return(true);
  }

//+------------------------------------------------------------------+
bool ParsePacComment(const string cmt, bool &isBuy, int &pos, double &cl, string &ts)
  {
   PacCmt p;
   if(!ParsePacCommentEx(cmt, p))
      return(false);
   isBuy = p.isBuy;
   pos   = p.position;
   cl    = p.clPrice;
   ts    = p.stamp;
   return(true);
  }

//+------------------------------------------------------------------+
bool SameCl(const double a, const double b)
  {
   return(MathAbs(NormalizePrice(a) - NormalizePrice(b)) <= MathMax(PipSize() * 0.25, _Point));
  }

//+------------------------------------------------------------------+
bool PacScan(const bool wantBuy, const double cl, const int wantPos,
             const bool positions, const bool pendings, string &tsOut)
  {
   tsOut = "";
   if(positions)
     {
      const int np = PositionsTotal();
      for(int i = 0; i < np; i++)
        {
         const ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
         bool buy = false;
         int pos = 0;
         double ccl = 0.0;
         string ts = "";
         if(!ParsePacComment(PositionGetString(POSITION_COMMENT), buy, pos, ccl, ts))
            continue;
         if(buy != wantBuy)
            continue;
         if(wantPos > 0 && pos != wantPos)
            continue;
         if(!SameCl(ccl, cl))
            continue;
         tsOut = ts;
         return(true);
        }
     }
   if(pendings)
     {
      const int no = OrdersTotal();
      for(int i = 0; i < no; i++)
        {
         const ulong ticket = OrderGetTicket(i);
         if(ticket == 0 || !OrderSelect(ticket))
            continue;
         if(OrderGetString(ORDER_SYMBOL) != _Symbol)
            continue;
         if(OrderGetInteger(ORDER_MAGIC) != InpMagic)
            continue;
         bool buy = false;
         int pos = 0;
         double ccl = 0.0;
         string ts = "";
         if(!ParsePacComment(OrderGetString(ORDER_COMMENT), buy, pos, ccl, ts))
            continue;
         if(buy != wantBuy)
            continue;
         if(wantPos > 0 && pos != wantPos)
            continue;
         if(!SameCl(ccl, cl))
            continue;
         tsOut = ts;
         return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
bool HasPacSide(const bool isBuy, const double cl, string &tsOut)
  {
   return(PacScan(isBuy, cl, 0, true, true, tsOut));
  }

//+------------------------------------------------------------------+
bool HasPacLayer(const bool isBuy, const double cl, const int pos)
  {
   string ts = "";
   return(PacScan(isBuy, cl, pos, true, true, ts));
  }

//+------------------------------------------------------------------+
bool HasPacPosition(const bool isBuy, const double cl)
  {
   string ts = "";
   return(PacScan(isBuy, cl, 0, true, false, ts));
  }

//+------------------------------------------------------------------+
bool HasQueuedReentry(const bool isBuy, const double cl)
  {
   const int n = ArraySize(g_tpBatches);
   for(int i = 0; i < n; i++)
     {
      for(int s = 0; s < ArraySize(g_tpBatches[i].slots); s++)
        {
         PacCmt p;
         if(!ParsePacCommentEx(g_tpBatches[i].slots[s].comment, p))
            continue;
         if(p.isBuy == isBuy && SameCl(p.clPrice, cl))
            return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
void CancelStalePendings(const double &liveCl[], const bool &liveBuy[], const int nLive)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      PacCmt p;
      if(!ParsePacCommentEx(OrderGetString(ORDER_COMMENT), p))
         continue;
      const bool buy = p.isBuy;
      const double ccl = p.clPrice;
      bool current = false;
      for(int k = 0; k < nLive; k++)
        {
         if(liveBuy[k] == buy && SameCl(liveCl[k], ccl))
           {
            current = true;
            break;
           }
        }
      if(current)
         continue;
      const string cmt = OrderGetString(ORDER_COMMENT);
      if(g_trade.OrderDelete(ticket) && TradeOk())
        {
         Print("PAC geser: hapus pending grup jauh ", cmt);
         DropTpBatchesForGroup(p.groupCode);
        }
     }
  }

//+------------------------------------------------------------------+
void DropStaleTpBatches(const double &liveCl[], const bool &liveBuy[], const int nLive)
  {
   for(int i = ArraySize(g_tpBatches) - 1; i >= 0; i--)
     {
      const int gi = FindGroupIndex(g_tpBatches[i].groupCode);
      bool live = false;
      if(gi >= 0)
        {
         const bool buy = (g_groups[gi].direction > 0);
         for(int k = 0; k < nLive; k++)
           {
            if(liveBuy[k] == buy && SameCl(liveCl[k], g_groups[gi].clPrice))
              {
               live = true;
               break;
              }
           }
        }
      if(!live)
         RemoveTpBatchAt(i);
     }
  }

//+------------------------------------------------------------------+
void BuildLiveSlots(double &liveCl[], bool &liveBuy[], int &nLive,
                    int &buyIdx[], int &nBuy, int &sellIdx[], int &nSell)
  {
   nLive = 0;
   ArrayResize(liveCl, 0);
   ArrayResize(liveBuy, 0);
   nBuy = 0;
   nSell = 0;
   ArrayResize(buyIdx, 0);
   ArrayResize(sellIdx, 0);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0)
      return;
   LiveItem items[];
   CollectItems(items);
   const double maxW = MathMax(InpMaxAreaWidth, 1) * PipSize();
   const double pip  = PipSize();
   double keepB[];
   double keepS[];
   int nkb = 0;
   int nks = 0;
   CollectNearestZones(true, bid, maxW, buyIdx, nBuy, keepB, nkb, items);
   CollectNearestZones(false, bid, maxW, sellIdx, nSell, keepS, nks, items);
   for(int i = 0; i < nBuy; i++)
     {
      const double cl = NormalizePrice(g_zones[buyIdx[i]].low - MathMax(InpCLBuffer, 0) * pip);
      nLive++;
      ArrayResize(liveCl, nLive);
      ArrayResize(liveBuy, nLive);
      liveCl[nLive - 1]  = cl;
      liveBuy[nLive - 1] = true;
     }
   for(int i = 0; i < nkb; i++)
     {
      bool dup = false;
      for(int k = 0; k < nLive; k++)
        {
         if(liveBuy[k] && SameCl(liveCl[k], keepB[i]))
           {
            dup = true;
            break;
           }
        }
      if(dup)
         continue;
      nLive++;
      ArrayResize(liveCl, nLive);
      ArrayResize(liveBuy, nLive);
      liveCl[nLive - 1]  = keepB[i];
      liveBuy[nLive - 1] = true;
     }
   for(int i = 0; i < nSell; i++)
     {
      const double cl = NormalizePrice(g_zones[sellIdx[i]].high + MathMax(InpCLBuffer, 0) * pip);
      nLive++;
      ArrayResize(liveCl, nLive);
      ArrayResize(liveBuy, nLive);
      liveCl[nLive - 1]  = cl;
      liveBuy[nLive - 1] = false;
     }
   for(int i = 0; i < nks; i++)
     {
      bool dup = false;
      for(int k = 0; k < nLive; k++)
        {
         if(!liveBuy[k] && SameCl(liveCl[k], keepS[i]))
           {
            dup = true;
            break;
           }
        }
      if(dup)
         continue;
      nLive++;
      ArrayResize(liveCl, nLive);
      ArrayResize(liveBuy, nLive);
      liveCl[nLive - 1]  = keepS[i];
      liveBuy[nLive - 1] = false;
     }
  }

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
bool TradeOk()
  {
   const uint r = g_trade.ResultRetcode();
   return(r == TRADE_RETCODE_DONE ||
          r == TRADE_RETCODE_DONE_PARTIAL ||
          r == TRADE_RETCODE_PLACED ||
          r == TRADE_RETCODE_NO_CHANGES);
  }

//+------------------------------------------------------------------+
bool PlacePending(const bool isBuy, const double lot, const double price,
                  const double sl, const double tp, const string comment)
  {
   string newsName = "";
   if(InNewsWindow(newsName))
      return(false);
   string hourLabel = "";
   if(InHourFilterWindow(hourLabel))
      return(false);
   const ENUM_ORDER_TYPE type = SelectPendingType(isBuy, price);
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   bool ok = false;
   if(type == ORDER_TYPE_BUY_LIMIT)
      ok = g_trade.BuyLimit(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
   else if(type == ORDER_TYPE_BUY_STOP)
      ok = g_trade.BuyStop(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
   else if(type == ORDER_TYPE_SELL_LIMIT)
      ok = g_trade.SellLimit(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
   else if(type == ORDER_TYPE_SELL_STOP)
      ok = g_trade.SellStop(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
   if(ok && TradeOk())
      return(true);
   Print("PAC order gagal: ", comment, " ret=", g_trade.ResultRetcode(),
         " ", g_trade.ResultRetcodeDescription());
   return(false);
  }

//+------------------------------------------------------------------+
void SendSide(const bool isBuy, const bool paired, const double extreme, const double tp,
              const string ts)
  {
   const int n = LayerCount();
   double cl = 0.0;
   double sl = 0.0;
   double entry1 = 0.0;
   CalcEntryClSl(isBuy, extreme, tp, entry1, cl, sl);
   const double tpN = NormalizePrice(tp);
   string dummy = "";
   if(HasPacSide(isBuy, cl, dummy) || HasQueuedReentry(isBuy, cl))
      return;

   for(int i = 1; i <= n; i++)
     {
      if(HasPacLayer(isBuy, cl, i))
         continue;
      double entry = entry1 + (extreme - entry1) * (double)(i - 1) / (double)n;
      entry = NormalizePrice(entry);
      const string cmt = MakeComment(paired, isBuy, n, i, cl, ts);
      const double lot = LayerLot(i);
      if(PlacePending(isBuy, lot, entry, sl, tpN, cmt))
         Print("PAC pending: ", cmt, " @ ", DoubleToString(entry, _Digits),
               " lot ", DoubleToString(lot, 2));
     }
  }

//+------------------------------------------------------------------+
//| Cari extreme (high/low) zona lawan terdekat dari daftar slot     |
//| aktif+kandidat, buat cegah TP mandiri crossing kalau ternyata    |
//| ada zona lawan yg jaraknya < maxW. Return 0 kalau tidak ada.     |
//+------------------------------------------------------------------+
double NearestOppositeExtreme(const bool isBuy, const double extreme,
                              const double &liveCl[], const bool &liveBuy[], const int nLive)
  {
   const double buf = MathMax(InpCLBuffer, 0) * PipSize();
   double best = 0.0;
   double bestDist = DBL_MAX;
   for(int i = 0; i < nLive; i++)
     {
      if(liveBuy[i] == isBuy)
         continue;
      const double oppExtreme = liveBuy[i] ? (liveCl[i] + buf) : (liveCl[i] - buf);
      double dist = 0.0;
      if(isBuy)
        {
         if(oppExtreme <= extreme)
            continue;
         dist = oppExtreme - extreme;
        }
      else
        {
         if(oppExtreme >= extreme)
            continue;
         dist = extreme - oppExtreme;
        }
      if(dist < bestDist)
        {
         bestDist = dist;
         best = oppExtreme;
        }
     }
   return(best);
  }

//+------------------------------------------------------------------+
//| TP mandiri (extreme +/- maxW/2), tapi di-clamp ke titik tengah   |
//| kalau ada zona lawan lebih dekat dari maxW supaya TP dua sisi    |
//| tidak saling menyeberang (crossing).                             |
//+------------------------------------------------------------------+
double IndependentTp(const bool isBuy, const double extreme, const double maxW,
                     const double &liveCl[], const bool &liveBuy[], const int nLive)
  {
   double tp = isBuy ? (extreme + maxW * 0.5) : (extreme - maxW * 0.5);
   const double oppExtreme = NearestOppositeExtreme(isBuy, extreme, liveCl, liveBuy, nLive);
   if(oppExtreme <= 0.0)
      return(tp);
   const double gap = isBuy ? (oppExtreme - extreme) : (extreme - oppExtreme);
   if(gap < maxW)
      tp = (extreme + oppExtreme) * 0.5;
   return(tp);
  }

//+------------------------------------------------------------------+
void MaybeSendEligible(const int atapIdx, const int lantaiIdx, const bool paired,
                       const double maxW)
  {
   if(!InpSendOrders || InpLot <= 0.0)
      return;
   string newsName = "";
   if(InNewsWindow(newsName))
      return;
   string hourLabel = "";
   if(InHourFilterWindow(hourLabel))
      return;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
      return;

   const double pip = PipSize();

   int buyIdx[];
   int sellIdx[];
   int nBuy  = 0;
   int nSell = 0;
   double liveCl[];
   bool   liveBuy[];
   int    nLive = 0;
   BuildLiveSlots(liveCl, liveBuy, nLive, buyIdx, nBuy, sellIdx, nSell);
   CancelStalePendings(liveCl, liveBuy, nLive);
   DropStaleTpBatches(liveCl, liveBuy, nLive);

   datetime stamp = TimeCurrent();
   const bool pairKeep = (paired && atapIdx >= 0 && lantaiIdx >= 0 &&
                          IdxHas(sellIdx, nSell, atapIdx) &&
                          IdxHas(buyIdx, nBuy, lantaiIdx));

   if(pairKeep)
     {
      const double clS = NormalizePrice(g_zones[atapIdx].high + MathMax(InpCLBuffer, 0) * pip);
      const double clB = NormalizePrice(g_zones[lantaiIdx].low - MathMax(InpCLBuffer, 0) * pip);
      string tsS = "";
      string tsB = "";
      HasPacSide(false, clS, tsS);
      HasPacSide(true, clB, tsB);
      string ts = "";
      if(StringLen(tsS) > 0)
         ts = tsS;
      else if(StringLen(tsB) > 0)
         ts = tsB;
      else
        {
         ts = StampNow(stamp);
         stamp++;
        }
      const double tp = (g_zones[atapIdx].high + g_zones[lantaiIdx].low) * 0.5;
      if(!ClBrokenOnClosedBar(false, clS, DetectionTF()))
         SendSide(false, true, g_zones[atapIdx].high, tp, ts);
      if(!ClBrokenOnClosedBar(true, clB, DetectionTF()))
         SendSide(true, true, g_zones[lantaiIdx].low, tp, ts);
     }

   for(int i = 0; i < nBuy; i++)
     {
      const int z = buyIdx[i];
      if(pairKeep && z == lantaiIdx)
         continue;
      const double cl = NormalizePrice(g_zones[z].low - MathMax(InpCLBuffer, 0) * pip);
      string ts = "";
      if(!HasPacSide(true, cl, ts) || StringLen(ts) == 0)
        {
         ts = StampNow(stamp);
         stamp++;
        }
      const double tp = IndependentTp(true, g_zones[z].low, maxW, liveCl, liveBuy, nLive);
      SendSide(true, false, g_zones[z].low, tp, ts);
     }
   for(int i = 0; i < nSell; i++)
     {
      const int z = sellIdx[i];
      if(pairKeep && z == atapIdx)
         continue;
      const double cl = NormalizePrice(g_zones[z].high + MathMax(InpCLBuffer, 0) * pip);
      string ts = "";
      if(!HasPacSide(false, cl, ts) || StringLen(ts) == 0)
        {
         ts = StampNow(stamp);
         stamp++;
        }
      const double tp = IndependentTp(false, g_zones[z].high, maxW, liveCl, liveBuy, nLive);
      SendSide(false, false, g_zones[z].high, tp, ts);
     }
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
bool IsBuyOrderType(const ENUM_ORDER_TYPE t)
  {
   return(t == ORDER_TYPE_BUY || t == ORDER_TYPE_BUY_LIMIT ||
          t == ORDER_TYPE_BUY_STOP || t == ORDER_TYPE_BUY_STOP_LIMIT);
  }

//+------------------------------------------------------------------+
bool ClBrokenOnClosedBar(const bool isBuy, const double cl, const ENUM_TIMEFRAMES tf)
  {
   const double c = iClose(_Symbol, tf, 1);
   if(c <= 0.0)
      return(false);
   if(isBuy)
      return(c < cl);
   return(c > cl);
  }

//+------------------------------------------------------------------+
bool DealProcessed(const ulong deal)
  {
   const int n = ArraySize(g_processedDeals);
   for(int i = 0; i < n; i++)
     {
      if(g_processedDeals[i] == deal)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
void MarkDealProcessed(const ulong deal)
  {
   const int n = ArraySize(g_processedDeals);
   ArrayResize(g_processedDeals, n + 1, 64);
   g_processedDeals[n] = deal;
   if(n > 400)
     {
      for(int i = 0; i < n - 200; i++)
         g_processedDeals[i] = g_processedDeals[i + 200];
      ArrayResize(g_processedDeals, n - 200);
     }
  }

//+------------------------------------------------------------------+
int FindGroupIndex(const string code)
  {
   const int n = ArraySize(g_groups);
   for(int i = 0; i < n; i++)
     {
      if(g_groups[i].groupCode == code)
         return(i);
     }
   return(-1);
  }

//+------------------------------------------------------------------+
int FindZoneIndexForCl(const bool isBuy, const double cl)
  {
   const double maxW = MathMax(InpMaxAreaWidth, 1) * PipSize();
   const int nz = ArraySize(g_zones);
   for(int z = 0; z < nz; z++)
     {
      if(g_zones[z].isSupport != isBuy)
         continue;
      double zcl = 0.0;
      double ztp = 0.0;
      ZoneClTp(g_zones[z], maxW, zcl, ztp);
      if(SameCl(zcl, cl))
         return(z);
     }
   return(-1);
  }

//+------------------------------------------------------------------+
bool GroupPivotCapReached(const PacGroup &g)
  {
   const int z = FindZoneIndexForCl(g.direction > 0, g.clPrice);
   if(z < 0)
      return(false);
   return(g_zones[z].pivotTouches >= MaxPivotTouches());
  }

//+------------------------------------------------------------------+
int FindBatchIndex(const string code)
  {
   const int n = ArraySize(g_tpBatches);
   for(int i = 0; i < n; i++)
     {
      if(g_tpBatches[i].groupCode == code)
         return(i);
     }
   return(-1);
  }

//+------------------------------------------------------------------+
int FindSnapIndex(const ulong positionId)
  {
   const int n = ArraySize(g_snaps);
   for(int i = 0; i < n; i++)
     {
      if(g_snaps[i].positionId == positionId)
         return(i);
     }
   return(-1);
  }

//+------------------------------------------------------------------+
void UpsertPositionSnapshot(const ulong posTicket)
  {
   if(posTicket == 0 || !PositionSelectByTicket(posTicket))
      return;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return;
   if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
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
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      LiveItem it;
      it.ticket     = ticket;
      it.positionId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      it.isPosition = true;
      it.comment    = PositionGetString(POSITION_COMMENT);
      it.price      = PositionGetDouble(POSITION_PRICE_OPEN);
      it.sl         = PositionGetDouble(POSITION_SL);
      it.tp         = PositionGetDouble(POSITION_TP);
      it.lot        = PositionGetDouble(POSITION_VOLUME);
      it.orderType  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                      ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      it.setupTime  = (datetime)PositionGetInteger(POSITION_TIME);
      it.parsed     = ParsePacCommentEx(it.comment, it.pac);
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
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;

      LiveItem it;
      it.ticket     = ticket;
      it.positionId = 0;
      it.isPosition = false;
      it.comment    = OrderGetString(ORDER_COMMENT);
      it.price      = OrderGetDouble(ORDER_PRICE_OPEN);
      it.sl         = OrderGetDouble(ORDER_SL);
      it.tp         = OrderGetDouble(ORDER_TP);
      it.lot        = OrderGetDouble(ORDER_VOLUME_CURRENT);
      if(it.lot <= 0.0)
         it.lot = OrderGetDouble(ORDER_VOLUME_INITIAL);
      it.orderType  = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      it.setupTime  = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      it.parsed     = ParsePacCommentEx(it.comment, it.pac);
      const int n = ArraySize(items);
      ArrayResize(items, n + 1);
      items[n] = it;
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
bool ItemMatchesGroup(const LiveItem &it, const PacGroup &g)
  {
   if(!it.parsed)
      return(false);
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
bool IsClBreak(const PacGroup &g, const double closePrice)
  {
   if(g.direction > 0)
      return(closePrice < g.clPrice);
   return(closePrice > g.clPrice);
  }

//+------------------------------------------------------------------+
void FlattenGroup(PacGroup &g)
  {
   LiveItem items[];
   CollectItems(items);
   for(int i = 0; i < ArraySize(items); i++)
     {
      if(!ItemMatchesGroup(items[i], g))
         continue;
      if(items[i].isPosition)
        {
         if(!g_trade.PositionClose(items[i].ticket) || !TradeOk())
            Print("PAC CLCC gagal tutup posisi #", items[i].ticket, " grup ", g.groupCode);
        }
      else
        {
         if(!g_trade.OrderDelete(items[i].ticket) || !TradeOk())
            Print("PAC CLCC gagal hapus pending #", items[i].ticket, " grup ", g.groupCode);
        }
     }
  }

//+------------------------------------------------------------------+
void DropTpBatchesForGroup(const string code)
  {
   for(int i = ArraySize(g_tpBatches) - 1; i >= 0; i--)
     {
      if(g_tpBatches[i].groupCode == code)
         RemoveTpBatchAt(i);
     }
  }

//+------------------------------------------------------------------+
void ExecuteClcc(PacGroup &g)
  {
   g.clExecuted = true;
   g_clccGroup  = g.groupCode;
   RememberClcc(g);
   DropTpBatchesForGroup(g.groupCode);
   FlattenGroup(g);
   ApplyClccToZones();
   const string msg = "PAC CLCC " + _Symbol + " " + (g.direction > 0 ? "Buy " : "Sell ") + g.groupCode +
                      " — pending dihapus, tidak reentry";
   Print(msg);
   if(InpAlertOnCL)
      Alert(msg);
   g_clccGroup = "";
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
            Print("PAC CLCC catch-up ", g.groupCode, " close[", i, "]=", DoubleToString(cl, _Digits));
            g.lastCheckedBarTime = currentBar;
            ExecuteClcc(g);
            return;
           }
        }
     }
   g.lastCheckedBarTime = currentBar;
  }

//+------------------------------------------------------------------+
void SyncGroups(const LiveItem &items[])
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

      PacGroup g;
      g.groupCode           = items[i].pac.groupCode;
      g.timeframe           = items[i].pac.timeframe;
      g.clPrice             = items[i].pac.clPrice;
      g.tfText              = items[i].pac.tfText;
      g.layerCount          = items[i].pac.layerCount;
      g.direction           = IsBuyOrderType(items[i].orderType) ? 1 : -1;
      g.startedAt           = items[i].setupTime;
      g.lastCheckedBarTime  = 0;
      g.reentryCount        = 0;
      g.clExecuted          = false;

      for(int j = 0; j < nItems; j++)
        {
         if(!items[j].parsed)
            continue;
         if(items[j].pac.groupCode != g.groupCode)
            continue;
         assigned[j] = true;
         if(items[j].setupTime < g.startedAt)
            g.startedAt = items[j].setupTime;
        }

      const int oldIdx = FindGroupIndex(g.groupCode);
      if(oldIdx >= 0)
        {
         g.lastCheckedBarTime = g_groups[oldIdx].lastCheckedBarTime;
         g.reentryCount       = g_groups[oldIdx].reentryCount;
         g.clExecuted         = g_groups[oldIdx].clExecuted;
        }
      else
         InitClccBarState(g);

      const int nn = ArraySize(next);
      ArrayResize(next, nn + 1);
      next[nn] = g;
     }

   for(int i = 0; i < ArraySize(g_groups); i++)
     {
      if(g_groups[i].clExecuted)
         continue;
      if(FindBatchIndex(g_groups[i].groupCode) < 0)
         continue;
      bool inNext = false;
      for(int j = 0; j < ArraySize(next); j++)
        {
         if(next[j].groupCode == g_groups[i].groupCode)
           {
            inNext = true;
            break;
           }
        }
      if(inNext)
         continue;
      const int nn = ArraySize(next);
      ArrayResize(next, nn + 1);
      next[nn] = g_groups[i];
     }

   ArrayResize(g_groups, ArraySize(next));
   for(int i = 0; i < ArraySize(next); i++)
      g_groups[i] = next[i];
  }

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
            Print("PAC CLCC ", g_groups[i].groupCode,
                  " TF=", g_groups[i].tfText,
                  " close=", DoubleToString(cl, _Digits),
                  " CL=", DoubleToString(g_groups[i].clPrice, _Digits));
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
void DeletePendingInGroup(PacGroup &g, const string tag)
  {
   LiveItem items[];
   CollectItems(items);
   int deleted = 0;
   for(int i = 0; i < ArraySize(items); i++)
     {
      if(items[i].isPosition || !ItemMatchesGroup(items[i], g))
         continue;
      if(!g_trade.OrderDelete(items[i].ticket) || !TradeOk())
         Print("PAC ", tag, " gagal hapus #", items[i].ticket);
      else
        {
         deleted++;
         Print("PAC ", tag, " hapus pending ", items[i].comment);
        }
     }
   if(deleted <= 0)
      return;
   const string msg = "PAC " + tag + " " + _Symbol + " " + g.groupCode +
                      " (" + IntegerToString(deleted) + " pending dihapus)";
   Print(msg);
   if(tag == "MaxReentry" && InpAlertOnReentry)
      Alert(msg);
  }

//+------------------------------------------------------------------+
void QueueTpReentry(const string groupCode, const Snapshot &snap)
  {
   int bi = FindBatchIndex(groupCode);
   if(bi < 0)
     {
      TpBatch b;
      b.groupCode     = groupCode;
      b.windowStartMs = GetTickCount64();
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
bool PlaceReentry(const TpSlot &slot)
  {
   PacCmt p;
   if(ParsePacCommentEx(slot.comment, p) && HasPacLayer(p.isBuy, p.clPrice, p.position))
      return(true);
   const double entry = NormalizePrice(slot.entry);
   const double lot   = NormalizeLot(slot.lot);
   if(PlacePending(slot.isBuy, lot, entry, slot.sl, slot.tp, slot.comment))
     {
      Print("PAC reentry: ", slot.comment, " @ ", DoubleToString(entry, _Digits));
      return(true);
     }
   return(false);
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

      if(GroupPivotCapReached(g_groups[gi]))
        {
         Print("PAC pivot cap ", code, " — tidak reentry");
         DeletePendingInGroup(g_groups[gi], "pivot cap");
         RemoveTpBatchAt(i);
         continue;
        }

      if(g_groups[gi].reentryCount >= MathMax(InpMaxReentry, 0))
        {
         DeletePendingInGroup(g_groups[gi], "MaxReentry");
         RemoveTpBatchAt(i);
         continue;
        }

      string newsName = "";
      if(InNewsWindow(newsName))
         continue;
      string hourLabel = "";
      if(InHourFilterWindow(hourLabel))
         continue;

      int okCount = 0;
      for(int s = 0; s < ArraySize(g_tpBatches[i].slots); s++)
        {
         if(PlaceReentry(g_tpBatches[i].slots[s]))
            okCount++;
        }

      if(okCount > 0)
        {
         g_groups[gi].reentryCount++;
         const string msg = "PAC Reentry " + _Symbol + " " + code + " " +
                            IntegerToString(g_groups[gi].reentryCount) + "/" +
                            IntegerToString(InpMaxReentry);
         Print(msg);
         if(InpAlertOnReentry)
            Alert(msg);
        }
      RemoveTpBatchAt(i);
     }
  }

//+------------------------------------------------------------------+
void ApplyNewsFilter()
  {
   string newsName = "";
   if(InNewsWindow(newsName))
     {
      if(newsName != g_lastNewsName)
        {
         Print("PAC news filter: ", newsName, " — tutup posisi & hapus pending");
         g_lastNewsName = newsName;
        }
      FlattenNewsExposure();
     }
   else
      g_lastNewsName = "";
  }

//+------------------------------------------------------------------+
//| Sama seperti ApplyNewsFilter — pakai ulang FlattenNewsExposure()  |
//| karena isinya generik (tutup semua posisi/pending simbol+magic    |
//| ini), bukan spesifik ke berita.                                   |
//+------------------------------------------------------------------+
void ApplyHourFilter()
  {
   string hourLabel = "";
   if(InHourFilterWindow(hourLabel))
     {
      if(hourLabel != g_lastHourFilterLabel)
        {
         string actionText = "cuma blokir entry baru";
         if(InpHourFilterMode == HOUR_FLATTEN_ALL)
            actionText = "tutup posisi & hapus pending";
         else if(InpHourFilterMode == HOUR_CANCEL_PENDING)
            actionText = "hapus pending, posisi terbuka jalan terus";
         Print("PAC hour filter: ", hourLabel, " — ", actionText);
         g_lastHourFilterLabel = hourLabel;
        }
      if(InpHourFilterMode == HOUR_FLATTEN_ALL)
         FlattenNewsExposure();
      else if(InpHourFilterMode == HOUR_CANCEL_PENDING)
        {
         ArrayResize(g_tpBatches, 0);
         CancelNewsPendings();
        }
      // HOUR_BLOCK_ENTRY_ONLY: jangan sentuh posisi/pending yang sudah ada;
      // entry baru sudah diblok lewat gate InHourFilterWindow() di tempat lain.
     }
   else
      g_lastHourFilterLabel = "";
  }

//+------------------------------------------------------------------+
void RefreshGroupsAndClcc()
  {
   LiveItem items[];
   CollectItems(items);
   UpdateSnapshots(items);
   SyncGroups(items);
   CheckAllClcc();
   for(int i = 0; i < ArraySize(g_groups); i++)
     {
      if(g_groups[i].clExecuted)
         FlattenGroup(g_groups[i]);
     }
  }

//+------------------------------------------------------------------+
void ApplyPivotCapAndSlots()
  {
   LiveItem items[];
   CollectItems(items);
   UpdateSnapshots(items);
   SyncGroups(items);

   for(int i = 0; i < ArraySize(g_groups); i++)
     {
      if(g_groups[i].clExecuted)
         continue;
      if(!GroupPivotCapReached(g_groups[i]))
         continue;
      Print("PAC pivot cap ", g_groups[i].groupCode, " — hapus pending, tidak reentry");
      DeletePendingInGroup(g_groups[i], "pivot cap");
      DropTpBatchesForGroup(g_groups[i].groupCode);
     }

   double liveCl[];
   bool   liveBuy[];
   int    nLive = 0;
   int    buyIdx[];
   int    sellIdx[];
   int    nBuy = 0;
   int    nSell = 0;
   BuildLiveSlots(liveCl, liveBuy, nLive, buyIdx, nBuy, sellIdx, nSell);
   CancelStalePendings(liveCl, liveBuy, nLive);
   DropStaleTpBatches(liveCl, liveBuy, nLive);
  }

//+------------------------------------------------------------------+
void ManageFast()
  {
   if(g_inRefresh)
      return;
   g_inRefresh = true;
   ApplyNewsFilter();
   ApplyHourFilter();
   ProcessTpBatches();
   g_inRefresh = false;
  }

//+------------------------------------------------------------------+
void ManageOrders()
  {
   if(g_inRefresh)
      return;
   g_inRefresh = true;
   ApplyNewsFilter();
   ApplyHourFilter();
   RefreshGroupsAndClcc();
   ApplyPivotCapAndSlots();
   ProcessTpBatches();
   g_inRefresh = false;
  }

//+------------------------------------------------------------------+
void HandleTradeTransaction(const MqlTradeTransaction &trans)
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
         ManageOrders();
      return;
     }

   if(trans.deal == 0 || DealProcessed(trans.deal))
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic)
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

   PacCmt pac;
   if(!ParsePacCommentEx(snap.comment, pac))
      return;

   const int gi = FindGroupIndex(pac.groupCode);
   if(gi < 0)
      return;
   if(g_groups[gi].clExecuted || g_clccGroup == pac.groupCode)
      return;
   if(WasClcc(pac.isBuy, pac.clPrice))
      return;
   if(reason == DEAL_REASON_EXPERT)
      return;

   if(reason == DEAL_REASON_TP)
     {
      QueueTpReentry(pac.groupCode, snap);
      if(!g_inRefresh)
         ManageOrders();
      return;
     }

   if(reason == DEAL_REASON_SL ||
      reason == DEAL_REASON_CLIENT ||
      reason == DEAL_REASON_MOBILE)
     {
      Print("PAC slot berhenti reentry: ", snap.comment, " reason=", reason);
      return;
     }
  }

//+------------------------------------------------------------------+
